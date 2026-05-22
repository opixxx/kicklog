---
name: code-review
description: >
  KickLog PR 자동 리뷰. 백엔드(backend/) 변경에 code-reviewer 호출,
  결과 통합 후 GitHub PR 코멘트로 등록. Use when: "PR 리뷰", "코드리뷰", "/code-review", PR 번호 언급.
  ※ iOS 영역은 자동 리뷰 대상 아님 (사용자가 Xcode 에서 직접 검토).
---

# PR 자동 리뷰 — 백엔드 서브에이전트 오케스트레이션

이 스킬은 **직접 리뷰하지 않는다**. 백엔드 변경이 있으면 `code-reviewer` 서브에이전트를 호출하고
결과를 통합하여 GitHub PR에 코멘트로 등록. iOS 변경은 검토에서 제외 (사용자 책임).

## 실행 방법

```
/code-review          → 현재 브랜치의 PR을 리뷰
/code-review 27       → PR #27을 리뷰
```

## Step 1: PR 컨텍스트 수집

```bash
PR_NUMBER="${1:-$(gh pr view --json number --jq '.number')}"

# PR 기본 정보
gh pr view "$PR_NUMBER" --json title,body,headRefName,baseRefName,files,additions,deletions,state

# 변경 diff
gh pr diff "$PR_NUMBER"

# 변경 파일 영역 분류
CHANGED_FILES=$(gh pr view "$PR_NUMBER" --json files -q '.files[].path')
BACKEND_CHANGED=$(echo "$CHANGED_FILES" | grep -c '^backend/' || true)
TF_CHANGED=$(echo "$CHANGED_FILES" | grep -c '^infra/terraform/' || true)
# iOS 변경은 무시 (자동 리뷰 대상 아님)

# CI 상태 (v1.1 도입 후)
gh pr checks "$PR_NUMBER" 2>/dev/null || echo "(CI 미설정)"
```

## Step 2: 서브에이전트 호출

Task 툴로 변경 영역에 따라 호출:

| 영역 변경 | 호출 에이전트 | 호출 조건 |
|---|---|---|
| `backend/**` 변경 | `code-reviewer` | BACKEND_CHANGED > 0 |
| `infra/terraform/**` 변경 | (수동 검토 권장) | TF_CHANGED > 0 — 보안 영향 큼 |
| 테스트 누락 (Plan에 명시되었으나 추가 안 됨) | `backend-test-writer` | 점검 목적, 작성은 X |
| `ios/**` 변경만 | (호출 없음 — 사용자 책임) | — |

### 에이전트 호출 — Task 툴

에이전트에게 PR 범위 전달:

```
PR #{번호}를 리뷰하세요.

- 변경 파일: {영역별 목록}
- 변경 diff: gh pr diff {PR번호} 로 직접 수집
- 대상 브랜치: {headRef} → {baseRef}

리뷰 기준:
- .codex/agents/{agent-name}.md 의 체크리스트 + 추가 학습 섹션
- 출력 형식: file:line, 심각도(Critical/Major/Minor), 카테고리, 위반 내용, 수정 제안
```

## Step 3: 결과 통합

### 3-1. Dedup
같은 file:line에 여러 에이전트가 동일 이슈 지적 시 (±3라인) 하나로 병합. 가장 높은 심각도와 가장 상세한 설명 채택.

### 3-2. 심각도 레이블 변환

| 에이전트 용어 | GitHub 레이블 | 머지 영향 |
|---|---|---|
| CRITICAL | 🔴 `[blocking]` | 반드시 수정 |
| MAJOR | 🟡 `[important]` | 수정 권장 |
| MINOR | 🟢 `[nit]` | 선택 |
| (대안 제시) | 💡 `[suggestion]` | 선택 |
| (칭찬) | 🎉 `[praise]` | — |

### 3-3. 카테고리 집계

```markdown
## 📊 리뷰 결과 요약

| 에이전트 | Critical | Major | Minor | 상태 |
|---|---|---|---|---|
| code-reviewer (backend) | 0 | 2 | 3 | 수정 권장 |
| **합계** | **0** | **2** | **3** | **💬 Comment** |
```

## Step 4: GitHub PR 코멘트 등록

### 4-1. 리뷰 본문 형식

```markdown
## 🤖 자동 코드리뷰 결과

{Step 3-3 요약 표}

### 🔴 Blocking ({개수}건)
{CRITICAL — file:line · 카테고리 · 위반 내용 · 수정 제안 · 에이전트명}

### 🟡 Important ({개수}건)
{MAJOR 항목}

### 🟢 Nit ({개수}건)
{MINOR 항목}

### 💡 Suggestions
{대안 제시}

### 🎉 Good Parts
{칭찬할 부분}

---

**리뷰 에이전트**: {호출된 agent 목록}
**누적 학습 반영**: 각 에이전트의 `memory: project` (`.codex/agent-memory/`)
```

### 4-2. 판정 결정

| 상태 | 조건 | 명령 |
|---|---|---|
| ✅ Approve | Critical 0건 + Major 0건 | `gh pr review {N} --approve --body "..."` |
| 💬 Comment | Critical 0건 + Major 있음 | `gh pr review {N} --comment --body "..."` |
| 🔄 Request Changes | Critical 1건 이상 | `gh pr review {N} --request-changes --body "..."` |

### 4-3. 인라인 코멘트

특정 라인에 대한 구체 피드백은 본문 리뷰가 아니라 **인라인 코멘트**:

```bash
gh api repos/{owner}/{repo}/pulls/{PR}/comments \
  -f body="🔴 [blocking] ..." \
  -f commit_id="$(gh pr view {PR} --json headRefOid -q .headRefOid)" \
  -f path="{file}" \
  -F line={line}
```

인라인 코멘트 기준:
- Critical/Major: 반드시 인라인
- Minor/Suggestion: 본문 요약만 (노이즈 방지)

## 이 스킬이 하지 않는 일

- **직접 체크리스트 대조** — 서브에이전트 고유 영역, 각 `.md`에서 관리
- **코드 수정** — 리뷰만, 수정은 PR 작성자 또는 `orchestrator`
- **테스트 추가/수정** — `*-test-writer`는 점검만 (작성은 orchestrator Phase 4에서만)
- **빌드/CI 실행** — `gh pr checks`로 조회만

## 에러 대응

| 상황 | 대응 |
|---|---|
| PR 번호 없음 | `gh pr view`로 현재 브랜치 PR 자동 조회, 없으면 사용자에게 안내 |
| backend 변경 없음 (ios/docs/infra만) | "백엔드 리뷰 대상 영역 없음 — iOS 는 자동 리뷰 제외" 안내 |
| 에이전트 타임아웃 | "N/A (타임아웃)"으로 표기 후 사용자 안내 |
| PR이 이미 머지됨 | "이미 머지된 PR, post-hoc 리뷰" 안내 후 코멘트만 등록 |

## 참조

- code-reviewer (backend): `.codex/agents/code-reviewer.md`
- backend-test-writer: `.codex/agents/backend-test-writer.md`
- 오케스트레이터 Phase 4: `.codex/skills/orchestrator/SKILL.md`
  (Phase 4는 **구현 중 리뷰**, 본 스킬은 **PR 생성 후 리뷰**. 호출 시점이 다름.)
