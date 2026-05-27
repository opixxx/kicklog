# ADR-0008: CD 자동 배포 — SSM Run Command + S3 staging + OIDC

- **Status**: Accepted
- **Date**: 2026-05-27
- **선행 ADR**: ADR-0006 (호스팅 — D7 "MVP 수동 배포, v1.1 CD", D10 SSH 본인 IP/32 정책), ADR-0007 (도메인 확정)

## Context

PR #47 에서 `appleboy/scp-action` + `appleboy/ssh-action` 기반 자동 CD 를 도입했으나, 첫 머지 직후 첫 실행이 다음과 같이 실패:

```
dial tcp ***:22: i/o timeout
```

원인은 EC2 Security Group `kicklog-ec2-sg` 의 SSH(22) 인바운드 룰이 `allowed_ssh_cidr = "<사용자 본인 IP>/32"` 로 좁혀져 있어(ADR-0006 D10) GitHub Actions runner 의 IP 가 차단되기 때문. ADR-0006 D7 에서 *"MVP 는 수동, v1.1+ 에서 GitHub Actions"* 로 결정해 둔 것을 앞당겨 CD 를 도입하면서 SSH 보안 룰과 충돌이 생긴 셈.

사용자 요구사항: **main 머지 시마다 자동 배포**. 따라서 SSH 보안 룰을 후퇴시키지 않으면서 CD 가 동작해야 한다.

---

## Options Considered

| 옵션 | 보안 | 변경 규모 | 평가 |
|---|---|---|---|
| (A) `allowed_ssh_cidr = "0.0.0.0/0"` | ❌ 후퇴 | 1줄 | ADR-0006 D10 정면 충돌 + SonarQube hotspot 재발. 비채택 |
| (B) Dynamic IP whitelist — runner IP 자가 추가/제거 | 🟡 중간 | cd.yml + IAM | 잔존 룰 위험. AWS credentials 도 어차피 필요해 (C) 대비 이점 적음 |
| (C) **SSM Run Command + S3 staging + OIDC** | ✅ 우수 | terraform + cd.yml 재설계 + ADR | 22 포트 의존 자체 제거. 정공법. **채택** |
| (D) Self-hosted runner on EC2 | 🟢 양호 | 큰 변경 | 1인 사이드엔 오버킬 |
| (E) deploy job 제거 → 수동 배포 | ✅ 유지 | 작음 | 사용자가 *자동 배포* 요구 — 비채택 |

---

## Decisions

### D1. 배포 채널 — **AWS SSM Run Command**

- **선택**: GitHub Actions 가 OIDC 로 IAM Role AssumeRole 후 `aws ssm send-command` 로 EC2 에 배포 스크립트 실행
- **이유**:
  - 22 포트 인바운드를 열 필요 자체가 사라짐 — ADR-0006 D10 정책 유지 가능
  - EC2 IAM Instance Profile + SSM Agent (AL2023 기본 설치) 만으로 동작
  - 사고 대응 시 Session Manager 로 SSH 없이 접근 가능 (별도 활용)
  - long-lived SSH key 를 GitHub Secrets 에서 제거 가능

### D2. 파일 전송 — **S3 staging bucket**

- **선택**: `kicklog-deploy-staging-${account_id}` 버킷에 `docker-compose.prod.yml` 업로드 → EC2 가 SSM script 안에서 `aws s3 cp` 로 다운로드
- **이유**:
  - SSM SendCommand 의 `--parameters` 에 파일 내용을 인라인하면 SSM history 에 평문 노출
  - 별도 S3 staging 으로 분리하면 lifecycle 7d expiration 도 자동 적용
- **버킷 정책**:
  - Public 접근 4축 모두 차단
  - SSE-S3 (AES256) 암호화
  - **HTTPS-only bucket policy** — `aws:SecureTransport=false` 인 요청 전면 Deny (SonarQube hotspot 정공법 반영)
  - Lifecycle: 7일 후 만료 (배포 산출물만 보관)
- **Access logging 미적용 (SonarQube hotspot Acknowledged)**:
  - 단일 writer(GitHub Actions OIDC role) + 단일 reader(EC2 IAM role) 구조 → audit 가치 낮음
  - 별도 log bucket 운영비/복잡도 대비 효용 부족 (1인 MVP)
  - 감사 필요 시 CloudTrail S3 Data Events 로 충분 (Free Tier 100k events/m)
  - 산출물 자체가 docker-compose.yml(평문, 비밀 없음) 1개라 민감도 낮음

### D3. 인증 — **GitHub OIDC + IAM AssumeRole**

- **선택**: `aws_iam_openid_connect_provider` (token.actions.githubusercontent.com) + `aws_iam_role` (StringLike `repo:opixxx/kicklog:ref:refs/heads/main`)
- **고려한 옵션**:
  - AWS Access Key/Secret 을 GitHub Secrets 에 저장 (long-lived, 유출 위험)
  - **OIDC — 선택**
- **이유**:
  - short-lived credential — long-lived secret 감소
  - sub claim 으로 main 브랜치 한정 — feature branch 에서 amend → push 했을 때 실수로 prod 배포 방지

### D4. 권한 범위 (최소 권한 원칙)

- GitHub Actions role 권한:
  - `s3:PutObject` only on `${deploy_staging_bucket}/*`
  - `ssm:SendCommand` only on EC2 instance ARN + `AWS-RunShellScript` document
  - `ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`
- EC2 role 추가 권한:
  - `AmazonSSMManagedInstanceCore` (managed policy, SSM Agent 통신)
  - `s3:GetObject` on `${deploy_staging_bucket}/*`
  - `secretsmanager:GetSecretValue` on `kicklog/ghcr-pat` (기존 3개 + 1개)

### D5. GHCR PAT — **AWS Secrets Manager 이전**

- **선택**: GitHub Secrets 의 `GHCR_PAT` 을 AWS Secrets Manager `kicklog/ghcr-pat` 으로 이전. EC2 가 SSM script 안에서 `aws secretsmanager get-secret-value` 로 가져와 docker login.
- **이유**:
  - SSM SendCommand parameter 에 평문 인라인 회피
  - 기존 db-password / kakao-rest-api-key / jwt-secret 과 동일 패턴 (일관성)

### D6. SSH 22 포트 룰 — **유지** (본 PR 스코프)

- **선택**: 본인 IP/32 룰은 유지 (비상 fallback)
- **이유**:
  - SSM 동작 검증 전 SSH 를 제거하면 사고 대응 채널 사라짐
  - 완전 제거는 본 PR 머지 + 몇 차례 안정 운영 후 별도 PR 에서 (Session Manager 가 SSH 대체 충분 확인 후)

### D7. 머지 후 사용자 수동 작업

PR 머지 전 1회:
1. `terraform.tfvars` 에 `ghcr_pat = "ghp_..."` 추가
2. `terraform apply` — IAM/S3/Secret 생성
3. `terraform output` 으로 ARN/bucket/instance-id 확인
4. GitHub repo Settings → Variables → 3개 등록 (`AWS_GITHUB_ROLE_ARN`, `DEPLOY_STAGING_BUCKET`, `EC2_INSTANCE_ID`)
5. GitHub repo Settings → Secrets → 기존 3개 삭제 (`EC2_HOST`, `EC2_SSH_PRIVATE_KEY`, `GHCR_PAT`)

---

## Consequences

### 긍정
- main 머지 자동 배포가 SSH 보안 정책을 후퇴시키지 않고 동작
- long-lived SSH key 가 GitHub Secrets 에서 사라짐 (공격 표면 ↓)
- 사용자가 EC2 접근 시에도 Session Manager 로 가능 → 본인 IP 변경 시 `terraform apply` 마찰 감소
- AWS 학습 가치 (OIDC, SSM, IAM least privilege) — ADR-0006 의 학습 가치 방향과 일치

### 부정 / 감수
- 추가 운영비:
  - S3 Standard ~$0/m (Free Tier 5GB)
  - Secrets Manager 1개 추가 +$0.40/m
- 초기 셋업 마찰 1회 (terraform apply + Variables 등록)
- CD 실패 시 디버깅 채널이 `aws ssm get-command-invocation` 으로 단일화 — SSM stdout/stderr 가 워크플로 로그에 출력되도록 cd.yml 에 명시

### Risk = Risky
- IAM/OIDC/S3 신규 + CD 동작 자체 재설계
- 롤백:
  1. PR revert
  2. `terraform apply` 로 신규 리소스 제거 (Secret 은 7d recovery window)
  3. GitHub Variables 제거, 기존 Secrets 복원
- fallback: SSH 22 룰 그대로 있어 사용자 본인 IP 에서 수동 `docker compose pull && up -d` 가능

---

## 후속 (별도 PR)

- ADR-0006 D10 의 SSH 22 룰 완전 제거 — Session Manager 만 사용 (안정 운영 확인 후)
- terraform state 를 S3 backend 로 이전 (ADR-0006 D8 후속)
- Immutable deploy — `ghcr.io/.../kicklog:${SHA}` tag 로 docker-compose 의 image 라인 동적화 (`envsubst` 또는 별도 도구)
- `api.kicklog.org` 서브도메인 + Let's Encrypt (ADR-0007 후속)
