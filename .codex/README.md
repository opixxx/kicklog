# .codex/ — Codex CLI 프로젝트 설정

KickLog의 Codex CLI 통합 설정. Claude Code의 `.claude/`와 평행 구조이며,
**같은 `tools/hooks/*.sh` 스크립트를 재사용**하므로 두 도구의 동작이 일관된다.

## 구성

```
.codex/
├── config.toml      # Hook + Skill + Agent 배선
├── agents/          # Codex custom agent role별 config layer
└── README.md        # 본 파일
```

## 작동 조건 — Trusted Project 등록

Codex는 **신뢰된 프로젝트의 `.codex/` 만 로드**한다. 처음 한 번 등록 필요.

### 방법 1: 자동 등록 (권장)
KickLog 디렉토리에서 처음으로 `codex` 실행 → 신뢰 여부를 묻는 프롬프트 → `Trust this project` 승인.

### 방법 2: 수동 등록 (`~/.codex/config.toml` 편집)
```toml
[projects."/Users/opix/Developer/kicklog"]
trust_level = "trusted"
```

> ⚠️ 신뢰 등록은 `.codex/config.toml`의 hook이 본인 머신에서 임의 명령을 실행할 권한을 부여한다.
> KickLog는 본인 저장소라 안전하지만, **남의 저장소를 클론한 경우엔 항상 `.codex/config.toml`을 검토 후 trust** 등록할 것.

## 활성화된 Hook

| 이벤트 | 매처 | 스크립트 | 역할 |
|---|---|---|---|
| `PreToolUse` | `^Bash$` | `tools/hooks/guard-bash.sh` | 위험 명령 차단 (rm -rf /, git push --force, DROP TABLE 등) |
| `SessionStart` | (모든) | `tools/hooks/session-context.sh` | 현재 worktree·브랜치·EXEC_PLAN·최근 커밋을 컨텍스트로 자동 주입 |
| `PreToolUse` | `^(Edit\|Write\|NotebookEdit)$` | `tools/hooks/enforce-worktree.sh` | main 메인 디렉토리에서 백엔드 소스 직접 수정 차단 (iOS 는 보호 대상 아님) |
| `PreToolUse` | `^(Edit\|Write\|NotebookEdit)$` | `tools/hooks/enforce-plan.sh` | 30줄 이상 코드 변경 시 EXEC_PLAN 강제 |
| `Stop` | (모든) | `tools/hooks/verify-and-block.sh` | linked worktree의 backend 변경에 대해 compileKotlin 검증 |

> Codex의 파일 편집 hook은 `apply_patch` 기반 입력을 사용한다. `Edit|Write` matcher 자체는 유효하지만,
> hook 스크립트가 Codex의 `tool_input.command` 패치 형식을 처리해야 완전한 차단이 된다.

## 등록된 Skills

Claude Code 원본 skill을 복사하지 않고 `.codex/config.toml`에서 직접 참조한다.

| Codex skill | 원본 |
|---|---|
| `orchestrator` | `.claude/skills/orchestrator/SKILL.md` |
| `pr-guide` | `.claude/skills/pr-guide/SKILL.md` |
| `code-review` | `.claude/skills/code-review/SKILL.md` |
| `coding-conventions` | `.claude/skills/coding-conventions/SKILL.md` |

Codex TUI에서 `/skills`로 노출 여부를 확인한다.

## 등록된 Agents

Claude Code 원본 agent markdown을 Codex custom agent role로 얇게 매핑한다.
원본 체크리스트와 상세 출력 형식은 `.claude/agents/*.md`가 계속 단일 진실 원천이다.

| Codex agent role | Config layer | 원본 |
|---|---|---|
| `code-reviewer` | `.codex/agents/code-reviewer.toml` | `.claude/agents/code-reviewer.md` |
| `backend-test-writer` | `.codex/agents/backend-test-writer.toml` | `.claude/agents/backend-test-writer.md` |

Codex TUI에서 subagent 생성 UI 또는 `/agent` 관련 기능으로 role 노출 여부를 확인한다.

## 검증 방법

### 1. 등록 확인
```bash
codex --help                   # CLI 정상 동작
ls ~/.codex/config.toml        # 글로벌 설정 존재
```

### 2. Hook 활성 여부
```bash
# Codex 세션 시작 → 첫 화면에 session-context.sh 출력이 보여야 함
codex
```

세션 시작 시 다음과 같은 컨텍스트가 자동 주입되면 성공:
```
📁 메인 작업 디렉토리
브랜치: main
최근 커밋: ...
```

### 3. 위험 명령 차단 검증
Codex 세션 내에서:
```
> rm -rf / 명령을 실행해줘
```
→ `guard-bash.sh`가 차단하고 `🚫 위험 명령 차단: rm -rf /` 메시지가 보여야 함.

### 4. Skills / Agents 등록 확인
```bash
codex --strict-config exec --help
```

설정 키 오류 없이 help가 출력되면 TOML key는 현재 Codex CLI에서 인식된다.
실제 TUI에서는 `/skills`, `/agent`, `/hooks`로 로드 상태와 hook trust 상태를 확인한다.

## Claude Code와의 관계

| 컴포넌트 | Claude Code | Codex |
|---|---|---|
| 글로벌 지침 | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` |
| 프로젝트 지침 | `CLAUDE.md` (루트) | `AGENTS.md` (루트) |
| 프로젝트 설정 | `.claude/settings.json` | `.codex/config.toml` (본 파일) |
| Hook 스크립트 | `tools/hooks/*.sh` ← 같은 파일 재사용 | `tools/hooks/*.sh` |
| Skills | `.claude/skills/**/SKILL.md` | `.codex/config.toml`의 `skills.config`로 원본 참조 |
| Agents | `.claude/agents/*.md` | `.codex/agents/*.toml` + `.codex/config.toml`의 `agents.<name>` |

**단일 진실 원천(SoT)**: hook 스크립트는 `tools/hooks/`에만 있고, Claude/Codex 양쪽이 동일한 스크립트를 호출한다. 동작 차이는 발생하지 않는다.
Skill/agent 상세 정책도 `.claude/**`를 원본으로 두고, Codex는 얇은 매핑 계층만 둔다.

## 트러블슈팅

### Hook이 실행되지 않음
1. **신뢰 등록 여부 확인**: `~/.codex/config.toml`의 `[projects."..."]` 항목
2. **스크립트 권한**: `ls -la tools/hooks/*.sh` — `x` 권한 확인
3. **TOML 문법**: `python3 -c "import tomllib; tomllib.load(open('.codex/config.toml','rb'))"`
4. **로그**: `~/.codex/log/codex-tui.log`

### Hook이 너무 자주 차단
`tools/hooks/guard-bash.sh`의 패턴이 너무 광범위하면 GearShow 원본을 참고해 정련. 다만 가능하면 패턴은 그대로 두고 명령을 안전한 방식으로 변경하는 게 원칙.

### Skills / Agents가 보이지 않음
1. Codex 버전 확인: `codex --version` (현재 검증 기준: `0.132.0`)
2. `/skills`에서 `orchestrator`, `pr-guide`, `code-review`가 보이는지 확인
3. `/agent` 또는 subagent 생성 UI에서 `code-reviewer`, `backend-test-writer` 가 보이는지 확인
4. 보이지 않으면 `/debug-config`로 project `.codex/config.toml` 레이어가 로드됐는지 확인
