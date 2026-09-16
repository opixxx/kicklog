# ADR-0013: SNS 알림 토픽 SSE 해제 — 암호화가 알람 통보를 막고 있었다

- **Status**: Accepted
- **Date**: 2026-09-16
- **선행 ADR**: ADR-0009 (free-tier 운영 격상 — D3 에서 SSE 활성을 결정)
- **번복 대상**: ADR-0009 D3 의 "SNS topic 에 AWS managed KMS key 로 SSE 활성"

## Context

2026-09-06 백엔드가 9일간 마비됐으나 **CloudWatch 알람이 한 건도 울리지 않았다**.
1차 원인은 알람 조건의 사각지대였고(StatusCheck 정상 / CPU 53%), 이를 메우려
앱 레벨 알람 2종을 추가했다 (`kicklog-backend-db-disconnected`, `kicklog-ec2-disk-read-surge`).

그 알람의 **통보 경로를 실제로 테스트**하는 과정에서 더 근본적인 문제가 드러났다.
알람을 강제로 ALARM 으로 전환했는데 **이메일이 오지 않았다.**

## 진단 (실측)

| 발행 주체 | 결과 |
|---|---|
| IAM 사용자(`kicklog-admin`)의 직접 `sns publish` | **성공** — Published 1 / Delivered 1 / Failed 0, 메일 수신 확인 |
| CloudWatch 알람의 상태 전환 | **발행 자체가 없음** (`NumberOfMessagesPublished` 무기록) |

`ActionsEnabled=true`, 알람 액션에 토픽 ARN 정상 연결, SNS 구독 `PendingConfirmation=false`.
설정은 전부 정상인데 **발행 단계에서 막혀 있었다.**

`alias/aws/sns` 키 정책을 조회한 결과:

```
Principal {AWS: *}                      → kms:Decrypt, kms:GenerateDataKey* (계정 내 IAM 주체)
Principal {Service: sns.amazonaws.com}  → kms:Decrypt
cloudwatch.amazonaws.com                → 없음
```

CloudWatch 가 암호화된 토픽에 발행하려면 `kms:GenerateDataKey*` 가 필요한데,
**AWS 관리형 키는 키 정책을 수정할 수 없다.** 따라서 이 조합에서는 알람 통보가 구조적으로 불가능하다.

**영향 범위**: 본 토픽을 쓰는 **모든 알람**. ADR-0009 D3 로 구축한 기존 4종
(`ec2-status-check-failed`, `ec2-high-cpu`, `rds-high-cpu`, `rds-low-storage`) 도 포함된다.
즉 **2026-05 구축 이래 어떤 알람도 통보된 적이 없다.**

## Decision

### D1. `aws_sns_topic.alerts` 의 `kms_master_key_id` 를 **제거**한다

- **고려한 옵션**
  - (A) **SSE 해제** — 무료. 통보 즉시 복구. **채택**
  - (B) 고객 관리형 CMK 생성 + 키 정책에 `cloudwatch.amazonaws.com` 허용 — 월 $1 + 호출 과금
  - (C) 유지하고 다른 통보 채널 추가 — 문제를 덮을 뿐
- **이유**
  - 본 토픽 메시지는 **알람 이름·메트릭 값·시각**뿐이다. PII/secret 이 없다.
  - 최종 전달 경로가 **이메일(SMTP)** 이라 어차피 평문으로 나간다.
    저장 시 암호화(SSE)의 실질적 보안 이득이 거의 없다.
  - ADR-0006/0009 의 free-tier 원칙상 월 $1 고정비는 과하다.
  - **작동하지 않는 알람은 알람이 아니다.** 통보 도달이 이 토픽의 존재 이유다.

### D2. 알람은 **통보 도달까지 검증**해야 도입이 끝난 것으로 본다

- 알람 생성 후 `aws cloudwatch set-alarm-state` 로 강제 전환해 **실제 수신을 확인**한다.
- `NumberOfMessagesPublished` / `NumberOfNotificationsDelivered` / `NumberOfNotificationsFailed`
  세 지표를 함께 본다. Published 가 없으면 발행 전 단계(권한·암호화)의 문제다.
- 이 원칙은 Sentry 에도 동일하게 적용된다 (같은 날 발견 — DSN 이 IAM 누락으로 빈 값이었다).

### D3. 정적 분석 지적은 본 ADR 을 근거로 예외 처리한다

ADR-0009 D3 의 SSE 활성은 SonarQube hotspot 해소가 동기였다.
정적 분석은 "암호화되지 않은 SNS 토픽"을 기계적으로 지적하지만, 이 토픽에서는
**암호화가 기능을 파괴한다.** 지적이 재발하면 본 ADR 을 근거로 예외 처리한다.

## Consequences

**긍정**
- 알람 통보가 실제로 도달한다. 2026-09-06 같은 장애를 15분 내 인지할 수 있다.
- 추가 비용 0.

**부정 / 감수**
- SNS 저장 시 암호화가 없다. 메시지에 민감 정보를 넣지 않는 것이 **전제 조건**이다.
  향후 알람 메시지에 식별자·토큰 등을 포함하려면 본 결정을 재검토해야 한다.
- 정적 분석에서 hotspot 이 다시 뜬다 (D3 로 처리).

## 교훈

**보안 설정이 기능을 조용히 파괴할 수 있다.** SSE 활성화는 그 자체로 옳은 방향이었지만,
CloudWatch 와의 상호작용을 검증하지 않아 알람 전체를 무력화했다. 게다가 실패가
**에러 없이 침묵으로** 나타나 4개월간 아무도 몰랐다.

같은 날 발견된 Sentry 비활성(IAM 누락 + `2>/dev/null` 로 에러 은폐)과 구조가 같다:
**설정은 완료됐지만 실제로는 동작하지 않았고, 실패가 조용했다.**
→ 관측·통보 계열 설정은 **엔드투엔드 수신 확인**을 완료 기준으로 삼는다.
