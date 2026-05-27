# Runbook — Terraform State 를 S3 Backend 로 이전

ADR-0006 D8 의 후속, ADR-0009 D6 에서 본 PR 미적용 결정. **체크리스트만 작성**, 실제 마이그레이션은 별도 PR.

> 대상: `infra/terraform/terraform.tfstate` (로컬) → `s3://kicklog-tfstate-<account-id>/infra/terraform.tfstate`
> 비용: < $0.05/m (S3 < 1MB + DynamoDB on-demand lock 또는 S3 native lockfile)
> 소요: 30~60분 (bootstrap + migrate-state + 검증)

---

## 1. 사전 결정

### Lock 메커니즘
| 옵션 | 비용 | 비고 |
|---|---|---|
| (A) S3 native lockfile (terraform 1.10+) | $0 | 새 기능, 별도 DynamoDB 불필요. **권장** |
| (B) DynamoDB lock table | < $0.01/m | 안정 검증된 전통적 방식. terraform < 1.10 호환 |

본 인프라는 `required_version = ">= 1.6.0"`, `Terraform v1.15.4` 사용 중 → **(A) S3 native** 채택.

### 버킷 이름 규칙
- 글로벌 유니크 필요 → `kicklog-tfstate-${account_id}` 와 같이 계정 ID suffix
- region: `ap-northeast-2` 일치
- 버전 관리: **활성화 필수** (state corruption 복구용)
- 암호화: SSE-S3 (AES256)
- public access block: 4축 모두 차단

---

## 2. Chicken-and-Egg 해결

S3 backend 를 정의하기 전에 S3 bucket 자체를 만들어야 한다. 3가지 패턴:

### 패턴 A — CLI 로 bucket 만 수동 생성 후 backend 적용 (가장 단순)
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="kicklog-tfstate-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "$BUCKET" \
  --region ap-northeast-2 \
  --create-bucket-configuration LocationConstraint=ap-northeast-2

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

bucket 자체는 terraform 관리 밖. 분실 시 같은 명령으로 재생성 가능하므로 OK.

### 패턴 B — bootstrap 모듈 분리
- `infra/terraform-bootstrap/` 디렉토리에 bucket 만 정의, 로컬 state 사용
- 한 번 apply 후 다시 건드릴 일 없음
- 본 PR 에서 채택할 경우 일이 두 배 — 패턴 A 권장

---

## 3. main.tf 의 backend 활성화

`infra/terraform/main.tf` 의 주석 블록을 활성화:

```hcl
terraform {
  required_version = ">= 1.10.0"  # S3 native lockfile 위해 상향

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.40" }
  }

  backend "s3" {
    bucket       = "kicklog-tfstate-<ACCOUNT_ID>"  # 실제 값
    key          = "infra/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true   # S3 native lock
  }
}
```

> `bucket` 에 변수 사용 불가 (terraform init 시점에 알아야 함). 하드코딩 또는 `-backend-config=` 로 주입.

---

## 4. State 마이그레이션

```bash
cd infra/terraform

# 1) 백업
cp terraform.tfstate terraform.tfstate.local-backup-$(date +%Y%m%d)

# 2) backend 활성화된 main.tf 로 init
terraform init -migrate-state

# Terraform 이 "Do you want to copy existing state to the new backend?" 질문 → yes

# 3) 검증
terraform state list   # 기존 리소스 모두 보여야 함
terraform plan          # No changes 이어야 함 (drift 없으면)
```

마이그레이션 성공 후:
- `terraform.tfstate` 로컬 파일은 **삭제하지 말고** `.gitignore` 에 그대로 두기
- `terraform.tfstate.backup` 은 한동안 보존
- `.local-backup-YYYYMMDD` 는 1주일 후 삭제

---

## 5. 검증 체크리스트

- [ ] `terraform state list` 가 마이그레이션 전과 동일한 리소스 목록
- [ ] `terraform plan` 결과 = "No changes"
- [ ] S3 bucket 에 `infra/terraform.tfstate` 객체 존재 (`aws s3 ls s3://<bucket>/infra/`)
- [ ] bucket versioning 활성화 확인 (`aws s3api get-bucket-versioning`)
- [ ] 두 번째 사용자 (있다면) 가 다른 머신에서 `terraform init` 후 `plan` 가능
- [ ] 한 사용자가 plan 도중 다른 사용자가 plan 시도하면 lock 에러 — `use_lockfile = true` 동작 확인

---

## 6. 롤백

마이그레이션 직후 문제 발견 시:

```bash
# main.tf 의 backend 블록을 다시 주석처리
# 로컬 backup 으로 복원
cp terraform.tfstate.local-backup-<date> terraform.tfstate
terraform init -reconfigure
# → "backend 가 사라졌는데 state 가 로컬에 있다" 경고에 yes
```

S3 bucket 자체는 그대로 두어도 비용 없음. 다음 시도 시 재사용.

---

## 7. 본 PR 미적용 사유 (ADR-0009 D6)

1. 본 PR 은 CD/관측성/SG 동시 변경 — state migration 까지 묶으면 롤백 단위 ↑
2. 1인 MVP 단계에 state 충돌 가능성 0 → 긴급도 낮음
3. terraform 1.10+ S3 native lockfile 의 운영 노하우가 사용자에게 누적된 후 진행하는 게 안전

대신 본 runbook 으로 절차를 코드화 — 별도 PR 시 바로 실행 가능.

---

## 참조

- ADR-0006 D8 (state 관리 결정)
- ADR-0009 D6 (본 PR 미적용 사유)
- Terraform S3 backend 공식: https://developer.hashicorp.com/terraform/language/backend/s3
- S3 native lockfile (terraform 1.10+) 공식: https://developer.hashicorp.com/terraform/language/backend/s3#state-locking
