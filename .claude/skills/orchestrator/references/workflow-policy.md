# Workflow Policy — Worktree + EXEC_PLAN + 검증

## Worktree 원칙

> **`main`/`master` 브랜치 메인 작업 디렉토리에서 백엔드/iOS 소스 직접 수정 금지.**
> 모든 코드 변경은 linked worktree 위에서.

### 판별
- `.git`이 **파일** → linked worktree (허용)
- `.git`이 **디렉토리** → 메인 작업 디렉토리 (소스 수정 차단)

### 절차
```bash
bash scripts/start-task.sh <task-name> <type>
```

스크립트가:
1. worktree (`../kicklog-<slug>`)
2. 브랜치 (`<type>/<slug>`)
3. 빈 포트 (9000~9099)
4. EXEC_PLAN 영구본 + worktree symlink
5. `.task/` 메타
6. `logs/`
7. 트레젝토리 기록 시작

완료 후:
```bash
git worktree remove ../kicklog-<slug>
```

### 브랜치 타입
- `feature/*` — 새 기능
- `fix/*` — 버그 수정
- `refactor/*` — 리팩토링 (동작 변경 없음)
- `chore/*` — 빌드·설정 변경
- `docs/*` — 문서만 변경

### 예외 (메인 디렉토리에서도 허용)

| 경로 | 이유 |
|---|---|
| `docs/**`, `*.md` | 문서 |
| `CLAUDE.md`, `AGENTS.md` | 하네스 자체 |
| `.claude/**`, `.codex/**` | 하네스 설정 |
| `tools/hooks/**`, `tools/templates/**` | 하네스 스크립트 |
| `scripts/start-task.sh` | 진입점 |
| `.github/**`, `.githooks/**` | CI |
| `.gitignore`, `.gitattributes` | 레포 설정 |
| `ios/README.md`, `ios/**/Assets.xcassets/**` | iOS 문서·에셋 |

그 외 모든 소스 (`backend/src/**`, `ios/KickLog/**/*.swift`, `ios/**/Info.plist` 등)는 linked worktree 필수.

## EXEC_PLAN 정책

### 30줄 임계 (단순화)

ADR-0001 기반 Ralph 원칙: "계획은 일회용, 짧게".

- **30줄 이상 변경** → EXEC_PLAN 필수
- **30줄 미만** → EXEC_PLAN 면제 (직접 수정 가능)

`enforce-plan.sh`가 자동 판단 (`git diff --cached --numstat` sum).

### 4섹션 (TDD 도입)

기존 GearShow의 8섹션 → KickLog는 4섹션:
1. **목표 (Goal)** — 왜 이 변경
2. **접근 (Approach)** — 시그니처 수준 (메서드·API·핵심 규칙)
3. **테스트 케이스 (Test Cases)** — TDD 핵심, Happy/Unhappy/Edge 분류
4. **검증 (Verification)** — Bash 명령으로 완료 조건

Optional 섹션:
- 위험도 / 롤백 (Risky 이상)
- 후속 / 관련 이슈

### TDD 강제 (enforce-plan.sh)

- 30줄 이상 변경 + `<TODO:>` 마커 남아있으면 차단
- 테스트 케이스 섹션도 채워야 함 (구현 전 작성 의무화)

## 영역별 검증 명령

### 백엔드 (Kotlin/Spring Boot 4)
```bash
cd backend
./gradlew compileKotlin       # 컴파일 (Stop 훅이 자동)
./gradlew test                # 테스트
./gradlew check               # 컴파일 + 테스트 + 정적 검사
```

### iOS (Swift/SwiftUI/SwiftData)
- Xcode에서 Cmd+B (실시간 컴파일)
- `xcodebuild -scheme KickLog test -destination 'platform=iOS Simulator,name=iPhone 16'`
- 시간 오래 걸려 자동 Stop 훅에서 제외 — 사용자 책임

### 인프라 (Terraform)
```bash
cd infra/terraform
terraform fmt -check
terraform validate
terraform plan
```

## 병렬 작업

여러 task 동시 진행 가능. 각 worktree는:
- 독립된 포트 (`.task/port`)
- 독립된 `logs/`
- 독립된 자가수정 카운터 (`/tmp/kicklog-selfheal/<worktree-slug>`)
