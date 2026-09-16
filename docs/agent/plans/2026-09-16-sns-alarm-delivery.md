# EXEC_PLAN — sns-alarm-delivery

| 항목 | 값 |
|---|---|
| Task | sns-alarm-delivery |
| Type | fix |
| Branch | fix/sns-alarm-delivery |
| 생성 시각 | 2026-09-16 |
| 상태 | `in-progress` |
| 개발 방식 | **인프라(terraform) — Kotlin 변경 없음, TDD 비적용** |

---

## 1. 목표

CloudWatch 알람의 통보가 **4개월간 한 번도 도달하지 않던** 문제를 고친다.

`kicklog-alerts` 토픽이 `alias/aws/sns`(AWS 관리형 키)로 SSE 되어 있어 CloudWatch 가
발행하지 못한다. AWS 관리형 키는 키 정책 수정이 불가능해 `cloudwatch.amazonaws.com` 에
`kms:GenerateDataKey*` 를 줄 수 없다. 상세는 **ADR-0013**.

## 2. 접근

| 파일 | 변경 |
|---|---|
| `infra/terraform/observability.tf` | `aws_sns_topic.alerts` 의 `kms_master_key_id` 제거 |
| `docs/adr/0013-sns-alarm-delivery.md` | 신규 — ADR-0009 D3 번복 결정 기록 |
| `docs/agent/learning.md` | 학습 항목 추가 |

SSE 해제를 택한 이유(ADR-0013 D1): 메시지에 PII/secret 이 없고, 최종 전달이 평문 SMTP 라
SSE 의 실질 이득이 거의 없다. 대안인 CMK 는 월 $1 + 호출 과금으로 free-tier 원칙에 어긋난다.

## 3. 검증 — 통보 도달까지가 완료 기준

### apply 전
- [x] `terraform validate`
- [ ] `terraform plan` → `aws_sns_topic.alerts` **in-place 수정 1건**만. 토픽 **재생성(destroy)이면 중단** — 구독이 날아간다

### apply 후 (핵심)
- [ ] `aws sns get-topic-attributes` → `KmsMasterKeyId` 없음
- [ ] 구독이 **그대로 유지**될 것 (`PendingConfirmation=false`, 같은 SubscriptionArn)
- [ ] **알람 강제 전환 → 실제 메일 수신 확인** ← 본 작업의 완료 조건
- [ ] `NumberOfMessagesPublished >= 1` (이번엔 알람이 주체) · `Delivered >= 1` · `Failed = 0`
- [ ] OK 복귀 후 정상 상태 확인

## 4. 위험도 / 롤백

**Risk: Caution** — `kms_master_key_id` 제거가 토픽 **재생성**을 유발하면 구독이 삭제되고
이메일 재확인이 필요해진다. **plan 에서 in-place 인지 반드시 확인**한다.

- in-place 면 무중단. 롤백은 `kms_master_key_id` 복원(단, 복원하면 통보가 다시 막힌다).
- 재생성이 필요하다면 apply 후 **구독 재생성 + 사용자의 이메일 확인 클릭**이 필요하다.

## 5. 후속

호스트 스왑 · healthcheck→재시작 연결 · iOS 방어 · `chore/ios-partial-harness` 머지(ADR-0012)

## 6. 학습 기록

- Trigger: production-risk
- Root cause: 보안 설정(SSE)이 기능(알람 통보)을 **에러 없이 침묵으로** 파괴했다.
- Prevention: 관측·통보 계열은 **엔드투엔드 수신 확인**을 완료 기준으로 삼는다.
- Promoted to: `docs/agent/learning.md` · **ADR-0013**
