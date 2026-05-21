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
- iOS `try? await` 결과 무시

## 로그 위치

- 검증 로그: `<worktree>/logs/verify-YYYYMMDD-HHMMSS.log`
- 카운터: `/tmp/kicklog-selfheal/<worktree-escaped>`
- 트레젝토리: `docs/agent/trajectories/YYYY-MM.log`

## 에스컬레이션 발동 시 보고 양식

```
🛑 자가수정 한계 초과
- 시도 횟수: 3/3
- 최종 실패 유형: <컴파일 | 테스트 | 기타>
- 로그 경로: <worktree>/logs/verify-*.log
- 지금까지 시도한 수정: <간단 요약>
- 다음 시도에 필요한 결정: <구체 질문>
```
