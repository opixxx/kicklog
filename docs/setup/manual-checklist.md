# 본인 수동 셋업 체크리스트

> 본 문서는 **사용자(본인)가 직접 본인 머신 / 외부 콘솔에서 수행**해야 할 작업 목록.
> Claude/Codex가 대신할 수 없는 작업 (계정 생성, 결제, 콘솔 UI, 비밀번호 관리 등).

---

## 0. 본인 머신 (개발 환경)

```bash
# 이미 확인됨 (2026-05-21 환경 검증):
# ✅ macOS / zsh
# ✅ git
# ✅ gh CLI (opixxx 인증)
# ✅ JDK 17 (sdkman temurin)
# ✅ Docker
# ✅ Xcode 16+ (xcode-select -p OK)

# 추가 설치 필요:
brew install terraform awscli
terraform version    # 1.6.0 이상 권장
aws --version
```

---

## 1. AWS — Terraform apply 전 사전 셋업

### 1.1 AWS 계정
- [ ] AWS 계정 생성 (또는 기존 사용)
- [ ] 결제 카드 등록
- [ ] Region: **서울(ap-northeast-2)** 기본 설정 확인

### 1.2 IAM 사용자 (Terraform 실행용)
- [ ] AWS Console → IAM → Users → Create user
  - 이름: `kicklog-terraform` (또는 본인 선호)
  - 권한: **AdministratorAccess** (MVP 단계, v1.1에서 최소 권한 좁힘)
  - Access Key 발급 → CSV 다운로드 (절대 안전 보관)

### 1.3 AWS CLI 자격증명
```bash
aws configure
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region name: ap-northeast-2
# Default output format: json

# 확인
aws sts get-caller-identity
```

### 1.4 EC2 Key Pair (SSH 접속용)
- [ ] AWS Console → EC2 → Key Pairs → Create
  - Name: `kicklog-keypair`
  - Type: ED25519 (또는 RSA 4096)
  - Format: `.pem`
- [ ] 다운로드된 `kicklog-keypair.pem`을 `~/.ssh/`로 이동
```bash
mv ~/Downloads/kicklog-keypair.pem ~/.ssh/
chmod 400 ~/.ssh/kicklog-keypair.pem
```

### 1.5 본인 IP 확인 (SSH 허용용)
```bash
curl ifconfig.me
# 결과: 121.140.xxx.xxx → terraform.tfvars의 allowed_ssh_cidr에 /32 추가
```

### 1.6 Budget Alarm (⚠️ 강력 권장)
- [ ] AWS Console → Billing → Budgets → Create budget
  - Type: **Monthly cost budget**
  - Amount: **$5/month** (MVP 무료 기간)
  - Notification: 본인 이메일 → 80%, 100% 도달 시
- [ ] 12개월 후 알람 갱신: $30/month 등으로 조정

---

## 2. 카카오 디벨로퍼 콘솔 — 외부 API 키 발급

### 2.1 카카오 계정
- [ ] https://developers.kakao.com 가입 (또는 기존 계정)

### 2.2 KickLog 애플리케이션 생성
- [ ] 내 애플리케이션 → 추가
  - 앱 이름: **KickLog**
  - 회사명: (본인 이름)
  - 아이콘: 추후 등록 가능

### 2.3 앱 키 확인
- [ ] 좌측 앱 키 메뉴에서 다음 키 확인 (각각 다른 용도):
  - **REST API 키** ← 백엔드 Spring Boot용 (Terraform `terraform.tfvars`에 `kakao_rest_api_key`)
  - **JavaScript 키** — 사용 X (웹용)
  - **Native App 키** ← iOS 앱용 (단계 3에서 KakaoOpenSDK 초기화)

### 2.4 플랫폼 등록
- [ ] **iOS 플랫폼 추가**
  - 좌측 플랫폼 → iOS 추가
  - 번들 ID: `com.opixxx.KickLog`
  - 마켓 URL: (App Store URL — 출시 후 추가, 지금은 비워둠)

### 2.5 카카오 로그인 활성화 (ADR-0003 D7)
- [ ] 좌측 카카오 로그인 → 활성화 설정 ON
- [ ] 동의항목 설정:
  - **닉네임** (필수 동의) — display_name 매핑용
  - **카카오계정(이메일)** (선택 동의) — 받으면 저장, 없으면 nullable
  - 프로필 이미지: v1.1+
- [ ] Redirect URI는 iOS 네이티브 SDK 사용이라 별도 설정 불필요

### 2.6 카카오 로컬 API (운동장 검색)
- [ ] 좌측 앱 설정 → 동의 항목 외에 추가 설정 없음
- [ ] 무료 한도: 일 300,000건 / 월 3,000,000건 — 충분

---

## 3. Apple Developer — Sign in with Apple (단계 3 이후 진행)

> ⚠️ Apple Sign-In 구현 + TestFlight 배포 단계에서 필요. 현재 (백엔드 코딩 시작 전) 단계에는 **불필요**.

### 3.1 Apple Developer Program 가입
- [ ] https://developer.apple.com → Enroll
- [ ] **$99/year** 결제 (개인 또는 회사)
- [ ] 가입 후 1~2일 검증 대기

### 3.2 App ID 등록
- [ ] Certificates, Identifiers & Profiles → Identifiers → +
  - Type: App IDs → App
  - Bundle ID: `com.opixxx.KickLog`
  - **Capabilities**:
    - ☑ Sign in with Apple
    - ☑ HealthKit
    - ☐ Background Modes (v1.1 푸시 알림 시 추가)

### 3.3 Sign in with Apple Service Key (백엔드 검증용)
- [ ] Keys → + → "KickLog Sign in with Apple"
  - ☑ Sign in with Apple
  - Configure → Primary App ID = `com.opixxx.KickLog`
- [ ] Key 생성 → `.p8` 파일 다운로드 (1회만 — 절대 안전 보관)
- [ ] Key ID + Team ID 메모 (백엔드 환경변수)

### 3.4 TestFlight 셋업 (정식 출시 전)
- [ ] App Store Connect → 앱 등록 → KickLog
- [ ] 본인+팀원 이메일로 TestFlight 베타 초대

---

## 4. GitHub — 이미 완료된 항목

- ✅ GitHub 계정 `opixxx`
- ✅ Private repo `opixxx/kicklog`
- ✅ gh CLI 인증
- 추후 (정식 출시 전):
  - [ ] Branch protection: main에 force push 금지, PR 리뷰 1+ 필수
  - [ ] GitHub Actions OIDC for AWS (v1.1)

---

## 5. (선택) 도메인 등록 — 정식 출시 직전

> ADR-0006 D7: MVP는 EC2 EIP 직접 접근, 정식 출시 시 도메인 등록.

- [x] 도메인 확정: `kicklog.org` (사용자 보유, ADR-0007)
- [ ] AWS Route 53 hosted zone 추가 (`$0.50/m`) — `kicklog.org` 와 `api.kicklog.org` 서브도메인
- [ ] Universal Link AASA (`/.well-known/apple-app-site-association`) 호스팅 — iOS Associated Domains 작업과 함께

---

## 6. Terraform 실행 흐름 (체크리스트 1~2 완료 후)

```bash
cd ~/Developer/kicklog/infra/terraform

# 1. 변수 파일 작성
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
# 채울 값:
# - ssh_key_name      = "kicklog-keypair"
# - allowed_ssh_cidr  = "본인IP/32"
# - rds_password      = "강한비밀번호16자+"
# - kakao_rest_api_key = "카카오 REST API 키"
# - jwt_secret        = "$(openssl rand -base64 32)"

# 2. 초기화
terraform init

# 3. 계획 검토 (NAT/ALB 등 비싼 리소스 없는지 확인)
terraform plan

# 4. 실제 생성 (5~10분)
terraform apply

# 5. SSH 접속 검증
$(terraform output -raw ssh_command)
```

상세 가이드: `infra/terraform/README.md`

---

## 7. 진행 상태 추적

| 영역 | 상태 |
|---|---|
| 본인 머신 도구 (terraform, awscli) | ⬜ 설치 필요 |
| AWS 계정 + IAM | ⬜ 본인 작업 필요 |
| AWS Key Pair | ⬜ |
| AWS Budget Alarm | ⬜ |
| 카카오 디벨로퍼 콘솔 | ⬜ 본인 작업 필요 |
| Terraform tfvars + apply | ⬜ |
| Apple Developer | ⬜ 단계 3 이후 |
| 도메인 | ⬜ 정식 출시 직전 |

---

## 8. 자주 묻는 질문

### Q. Terraform Free Tier로 시작했는데 비용 나오면?
A. **즉시 AWS Console > Billing > Cost Explorer** 확인. 가장 흔한 원인:
1. NAT Gateway 실수 추가 ($30/m) → `terraform.tfvars`에 NAT 변수 없음 확인
2. RDS 인스턴스 크기 t3.small 이상 ($25+/m) → variables.tf 확인
3. Data Transfer Out 100GB 초과 → 정상 운영에선 거의 발생 X
4. EIP 활성 인스턴스에서 분리 후 미반환 ($3.6/m) → `terraform destroy` 시 자동 정리

### Q. RDS Free Tier 12개월 어떻게 끝나는지 알 수 있나?
A. AWS Console → Billing → Free Tier 페이지에서 남은 기간 확인. 12개월 만료 1개월 전 이메일 알림.

### Q. 카카오 REST API 키 노출되면?
A. 카카오 디벨로퍼 콘솔 → 앱 키 → 재발급 → AWS Secrets Manager 업데이트 → EC2 재배포.

### Q. 인프라 잠시 중지하고 싶다 (휴가 등)
A. `terraform destroy` 후 휴가, 복귀 시 `terraform apply` 재실행. RDS 최종 스냅샷이 자동으로 보존되어 데이터 복원 가능.

---

## 참조

- ADR-0006 (호스팅): `docs/adr/0006-hosting.md`
- Terraform README: `infra/terraform/README.md`
- 카카오 디벨로퍼: https://developers.kakao.com
- AWS Console: https://console.aws.amazon.com
- Apple Developer: https://developer.apple.com
