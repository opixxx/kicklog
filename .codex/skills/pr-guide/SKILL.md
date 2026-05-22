---
name: pr-guide
description: KickLog Pull Request 생성. 백엔드 검증 → push → PR 생성 절차. iOS 변경은 검증 없이 통과 (사용자 책임).
---

# KickLog PR 생성

GitHub Pull Request를 생성하는 전체 절차. 테스트 실패 시 **절대 PR 생성하지 않는다.**

## 실행 절차

### Step 1: 사전 조건

```bash
gh auth status                  # gh CLI 인증
git branch --show-current       # main이 아닌지 확인
git status                      # 커밋되지 않은 변경 확인
```

커밋되지 않은 변경이 있으면 사용자에게 커밋 여부 확인.

#### worktree 환경 확인 (하네스)
```bash
TOP=$(git rev-parse --show-toplevel)
if [ -f "$TOP/.git" ]; then
  IN_WORKTREE="yes"
  PLAN_PATH="$TOP/EXEC_PLAN.md"
else
  IN_WORKTREE="no"
fi
```

- linked worktree (`$TOP/.git`이 파일)면 `EXEC_PLAN.md` 가능성 높음 → Step 5에서 PR 본문에 링크 포함
- 메인 디렉토리이면 플랜 없이 진행 (경고만 출력)

### Step 2: 영역별 검증 [필수]

> **모든 검증이 통과해야 PR을 생성한다.**

#### 백엔드 변경이 있는 경우
```bash
cd backend
./gradlew check                 # 컴파일 + 테스트 + 정적 검사
```

테스트 우선순위:
| 우선순위 | 유형 | 위치 |
|---|---|---|
| 1 | **Cucumber 인수 테스트** (있는 경우) | `src/test/resources/features/` |
| 2 | **통합 테스트** | 각 도메인 Service/Adapter |
| 3 | **단위 테스트** | 도메인 모델 |

#### iOS 변경이 있는 경우
- **자동 검증 없음.** 사용자가 Xcode 에서 Cmd+B 로 빌드 확인 (책임 사용자).

#### 인프라 변경이 있는 경우
```bash
cd infra/terraform
terraform fmt -check
terraform validate
terraform plan  # 사용자 검토 후 진행
```

#### 테스트 실패 시
1. 실패한 테스트 확인
2. 코드 수정 (기존 기능이 깨지지 않도록)
3. 재실행
4. **모든 테스트 통과 후에만 다음 단계**

### Step 3: 컨텍스트 수집

```bash
git branch --show-current
git log origin/main..HEAD --oneline
git diff origin/main..HEAD --stat
```

### Step 4: Push

```bash
git push origin HEAD
```

### Step 5: PR 생성

#### 브랜치 접두사 → PR 제목

| 접두사 | 커밋 prefix | 예시 |
|---|---|---|
| `feature/` | `feat:` | `feat: 친구 초대 링크 API 구현` |
| `fix/` | `fix:` | `fix: 쿼터 trim 슬라이더 시각 역행 버그` |
| `refactor/` | `refactor:` | `refactor: WorkoutAnalyzer 분리` |
| `chore/` | `chore:` | `chore: pre-commit hook 활성` |
| `docs/` | `docs:` | `docs: ADR-0005 작성` |

#### 2단계 커밋 (선택, Risky 이상 변경 권장)

| 분리 조건 | 권장 |
|---|---|
| Risk = Risky 이상 | ✅ |
| 메타 변경 라인 수 > 50 | ✅ |
| EXEC_PLAN 상태 갱신 | ✅ |
| 작은 변경 (Safe/Caution) | ❌ 단일 커밋 |

분리 형식:
```
1. feat({phase}): 핵심 변경 요약       (src/ 변경)
2. chore({phase}): 메타데이터 정리      (EXEC_PLAN/logs/.task/)
```

#### PR 본문 템플릿

```bash
gh pr create --title "PR 제목" --body "$(cat <<'EOF'
## Summary
- 변경 사항 요약 (1~3줄)

## EXEC_PLAN
- 📋 [실행 계획: {task-slug}](docs/agent/plans/{YYYY-MM-DD}-{task-slug}.md)
  (worktree 경유 작업이면 자동 삽입, 아니면 생략)

## Changes
- 구체적 변경 내용
- 파일/패키지 단위

## Test
백엔드:
- [ ] ./gradlew check 통과
- [ ] 통합 테스트 추가/유지
- [ ] DB 마이그레이션 (V?) 작성 (해당 시)

iOS:
- [ ] (사용자가 Xcode 에서 수동 확인 — 자동 검증 없음)

인프라:
- [ ] terraform fmt/validate 통과
- [ ] terraform plan 검토 — 비싼 리소스 없음

## Notes
- 리뷰어가 알아야 할 사항
- 후속 작업 계획

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" --base main
```

#### EXEC_PLAN 링크 자동 삽입

```bash
if [ "$IN_WORKTREE" = "yes" ] && [ -L "$PLAN_PATH" ]; then
  PLAN_TARGET=$(readlink "$PLAN_PATH")
  REPO_ROOT_MAIN=$(git -C "$TOP" worktree list --porcelain | awk '/^worktree/ && !found {print $2; found=1}')
  PLAN_REL="${PLAN_TARGET#$REPO_ROOT_MAIN/}"
fi
```

### Step 6: PR 생성 후

1. **PR URL 출력**
2. **CI 확인 안내** (GitHub Actions 빌드/테스트 자동 실행 — v1.1 도입 후)
3. **`/code-review` 스킬 호출 안내** (PR 자동 리뷰)

## 변경 영역 정책

### 단일 PR — 권장
- 백엔드만 변경
- iOS만 변경
- 백엔드 + iOS 같은 기능 — 작은 변경 시 합쳐도 OK

### 분할 PR — 권장
- 큰 변경 (>500줄)
- Breaking 변경과 호환성 변경 분리
- 인프라(terraform) + 백엔드 — 영역별 분리

## 에러 대응

| 상황 | 대응 |
|---|---|
| main 대비 커밋 없음 | 다른 브랜치에서 작업했는지 확인 |
| 브랜치 미push | `git push -u origin HEAD` |
| PR 이미 존재 | `gh pr view` 후 업데이트 여부 결정 |
| 머지 충돌 | 충돌 해결 후 rebase |
| 백엔드 test 실패 | 자가수정 또는 사용자 확인 |

## 최종 체크리스트

- [ ] `gh` CLI 인증
- [ ] 백엔드 변경 시 `./gradlew check` 통과
- [ ] iOS 변경 시 사용자가 Xcode 에서 수동 빌드 확인 (자동 검증 없음)
- [ ] terraform 변경 시 plan 검토
- [ ] 작업 디렉토리 clean
- [ ] 모든 커밋이 push됨
- [ ] PR 제목이 변경 내용 명확히 반영
- [ ] EXEC_PLAN 링크 포함 (worktree 경유 시)
- [ ] **보안 민감 정보 없음** (.env, API 키, JWT secret 등)
