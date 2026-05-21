# .codex/ — Codex CLI 프로젝트 설정

KickLog의 Codex CLI 통합 설정. Claude Code의 `.claude/`와 평행 구조이며,
**같은 `tools/hooks/*.sh` 스크립트를 재사용**하므로 두 도구의 동작이 일관된다.

## 구성

```
.codex/
├── config.toml      # Hook 배선 + 향후 프로젝트별 모델/승인 정책
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

## Claude Code와의 관계

| 컴포넌트 | Claude Code | Codex |
|---|---|---|
| 글로벌 지침 | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` |
| 프로젝트 지침 | `CLAUDE.md` (루트) | `AGENTS.md` (루트) |
| 프로젝트 설정 | `.claude/settings.json` | `.codex/config.toml` (본 파일) |
| Hook 스크립트 | `tools/hooks/*.sh` ← 같은 파일 재사용 | `tools/hooks/*.sh` |

**단일 진실 원천(SoT)**: hook 스크립트는 `tools/hooks/`에만 있고, Claude/Codex 양쪽이 동일한 스크립트를 호출한다. 동작 차이는 발생하지 않는다.

## 트러블슈팅

### Hook이 실행되지 않음
1. **신뢰 등록 여부 확인**: `~/.codex/config.toml`의 `[projects."..."]` 항목
2. **스크립트 권한**: `ls -la tools/hooks/*.sh` — `x` 권한 확인
3. **TOML 문법**: `codex --validate-config` (지원 시) 또는 다른 TOML 린터로 검증
4. **로그**: `~/.codex/log/codex-tui.log`

### Hook이 너무 자주 차단
`tools/hooks/guard-bash.sh`의 패턴이 너무 광범위하면 GearShow 원본을 참고해 정련. 다만 가능하면 패턴은 그대로 두고 명령을 안전한 방식으로 변경하는 게 원칙.

## 향후 단계 (단계 4)

Claude Code 단계 4 도입과 동시에 다음 hook을 `config.toml`에 추가 예정:

- `PreToolUse` (Edit/Write 매처) → `enforce-worktree.sh`, `enforce-plan.sh`
- `Stop` → `verify-and-block.sh` (compile만, iOS 제외)

상세는 [`.claude/skills/orchestrator/SKILL.md`](../.claude/skills/orchestrator/SKILL.md) (단계 4 도입 후).
