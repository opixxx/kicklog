# 자가수정 루프 (Self-healing Loop)

## 구성 요소

| 요소 | 역할 | 구현 |
|---|---|---|
| **훅** | 언제 검증할지 결정 | `.claude/settings.json` + `.codex/config.toml`의 `Stop` |
| **에이전트 (LLM)** | 실패 원인 분석·수정 결정 | Claude reasoning |
| **카운터 파일** | 언제 포기할지 결정 | `/tmp/kicklog-selfheal/<worktree>` |

훅은 "트리거", 에이전트는 "고치기", 카운터는 "포기 기준". 셋이 맞물려 돌아감.

## 반복 제한

| 반복 횟수 | 동작 |
|---|---|
| 1~2회 | 자동 자가수정 (구현 단계로 복귀) |
| 3회 연속 | **에스컬레이션** — 사람에게 도움 요청 |
| 동일 에러 메시지 3회 | 다른 접근 시도 또는 중단 |
| 총 30분 초과 | 중단 후 중간 상태 보고 |

## 허용되는 수정 패턴

- 컴파일 에러 → 문법 수정, import 추가, 타입 일치
- 테스트 실패 → 구현 로직 수정 또는 테스트 기대값 재검토 (테스트 무력화 금지)
- 실패 로그 분석 후 근본 원인 파악

## 금지된 수정 패턴

- 테스트 삭제·skip(`@Disabled`, `assumeTrue`) 처리로 우회
- `--no-verify`, `-DskipTests`, `--no-tests` 등으로 검증 우회
- 실패 원인 분석 없이 "다른 것을 시도" brute-force
- `try { ... } catch (e: Exception) { /* ignore */ }` 에러 삼키기

## 로그 위치

- 검증 로그: `<worktree>/logs/verify-YYYYMMDD-HHMMSS.log`
- 카운터: `/tmp/kicklog-selfheal/<worktree-escaped>`
- 트레젝토리: `docs/agent/trajectories/YYYY-MM.log`
- 학습 저널: `docs/agent/learning.md`

## 학습 승격

자가수정은 고치는 것으로 끝내지 않는다.

1. `verify-and-block.sh`는 compile 실패마다 trajectory에 `SELF_HEAL_ATTEMPT`를 남긴다.
2. 자가수정 후 검증이 통과하면 `SELF_HEAL_RESOLVED`를 남긴다.
3. 에이전트는 해결 후 다음을 판단한다.
   - 일회성 문법/타입 실수면 trajectory만 유지
   - 반복 가능하면 `docs/agent/learning.md`에 Root cause와 Prevention 추가
   - 계획 단계에서 막을 수 있으면 `tools/templates/EXEC_PLAN.template.md` 갱신
   - 리뷰로 잡아야 하면 `code-reviewer` memory/checklist 갱신
   - 테스트로 잡아야 하면 `backend-test-writer` memory 또는 `docs/spec/test-strategy.md` 갱신

학습 승격은 로컬 trajectory, agent memory, 프로젝트 문서를 단일 진실 원천으로 사용한다.

## 에스컬레이션 발동 시 보고 양식

```
🛑 자가수정 한계 초과
- 시도 횟수: 3/3
- 최종 실패 유형: <컴파일 | 테스트 | 기타>
- 로그 경로: <worktree>/logs/verify-*.log
- 지금까지 시도한 수정: <간단 요약>
- 다음 시도에 필요한 결정: <구체 질문>
```
