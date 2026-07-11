# Agent Learning Journal

자가수정, Critical 리뷰, 테스트 누락, 운영 리스크가 반복되지 않도록 실패를 재사용 가능한 규칙으로 승격하는 기록이다.

## When to Record

- `SELF_HEAL_ATTEMPT`가 trajectory에 남았다.
- `code-reviewer`가 Critical 또는 반복 Major를 지적했다.
- `backend-test-writer`가 누락된 인수/회귀 테스트를 발견했다.
- 구현이 테스트는 통과했지만 실제 의도와 어긋날 수 있는 reward hacking 가능성이 있었다.

## Promotion Rule

실패가 일회성 오타면 trajectory만 남긴다.
다음 중 하나라도 해당하면 이 파일과 관련 하네스를 갱신한다.

- 같은 유형이 2회 이상 반복될 수 있다.
- 보안, 인증, 인가, PII, 외부 API, DB 마이그레이션과 관련된다.
- 테스트가 없었다면 운영에서만 발견됐을 문제다.
- EXEC_PLAN에 적었다면 막을 수 있었던 누락이다.

## Update Targets

- `tools/templates/EXEC_PLAN.template.md`: 계획 단계에서 반드시 떠올려야 하는 항목.
- `.codex/agents/code-reviewer.md` / `.claude/agents/code-reviewer.md`: 리뷰 체크리스트로 잡아야 하는 항목.
- `.codex/agents/backend-test-writer.md` / `.claude/agents/backend-test-writer.md`: 테스트 작성 규칙으로 잡아야 하는 항목.
- `docs/spec/test-strategy.md`: 프로젝트 전체 테스트 전략.
- `docs/architecture/*.md` 또는 `docs/adr/*.md`: 설계 결정이나 운영 정책.

## Entry Template

```md
### YYYY-MM-DD — <pattern name>

- Trigger: self-heal | review-critical | missing-test | production-risk | security
- Task/PR:
- Failure:
- Root cause:
- Fix applied:
- Prevention:
- Updated:
  - [ ] EXEC_PLAN template
  - [ ] code-reviewer
  - [ ] backend-test-writer
  - [ ] test strategy
  - [ ] architecture/ADR
- Skip reason if not promoted:
```

## Learned Patterns

<!-- Add promoted learnings below. Keep entries short and actionable. -->

### 2026-05-27 — AWS Security Group description/name 은 immutable, RDS-attached 일 때 변경 불가

- Trigger: production-risk
- Task/PR: PR #50 (free-tier-prod-hardening), 1차 apply 실패
- Failure: `terraform apply` 가 RDS SG 를 destroy 시도 → `AuthFailure: detaching RDS ENI` 로 중단
- Root cause: SG `description` 변경을 정책 명문화 목적으로 추가했는데, AWS SG description 은 immutable → terraform 이 SG replace 시도 → RDS-managed ENI 는 RDS service 가 관리해 사용자(admin 포함)가 detach 불가
- Fix applied: SG description/name 을 ADR-0006 원본 그대로 복원. 정책 추가 정보는 HCL 주석으로만 남김
- Prevention:
  - 운영 중인 `aws_security_group` 의 `description` 과 `name` 은 한 번 정한 뒤 손대지 않는다 (정책 변경 시 ingress/egress rule 만 수정)
  - 표현 개선 / 정책 메모는 HCL 주석으로
  - `terraform plan` 출력에 `# forces replacement` 가 SG/EBS/IAM 등 stateful 리소스에 보이면 즉시 정지하고 사용자 확인
- Updated:
  - [x] architecture/ADR — ADR-0009 D5 에 함정 노트 추가
  - [x] code-reviewer (백엔드 전용이라 본 항목은 infra reviewer 가 생기면 이전)
  - [ ] EXEC_PLAN template
  - [ ] backend-test-writer (N/A — infra)
  - [ ] test strategy (N/A — infra)
- Skip reason if not promoted: N/A

---

### 2026-06-03 — 복제 부하테스트(트랙 C) 구동 함정 4종 + 측정 해석

- Trigger: production-risk (loadtest infra), 부하테스트 8080 미기동으로 다회 실패
- Task/ADR: 트랙 C iter1, ADR-0011, `infra/terraform-loadtest/`
- Failures & Root cause:
  1. **이미지 태그 형식**: `terraform.tfvars` 가 예시 placeholder(`backend_image_tag = "sha-xxxxxxx"`, `ghcr_pat = "ghp_xxx"`, `admin_cidr = "1.2.3.4/32"`) 그대로인데 `terraform apply` 는 값 검증 없이 성공 → EC2 user-data 안 docker pull 만 실패. README 가 `sha-<7>` 로 안내했으나 **GHCR 실제 태그는 full 40자 git SHA**(+`latest`) → `manifest unknown` → `set -euxo pipefail` user-data 가 침묵 중단 → 8080 미기동(connection refused).
  2. **user_data 변경 = in-place 갱신만**: 이미지/PAT 를 tfvars 에서 고쳐 `apply` 해도 `aws_instance` 는 in-place 로 user_data 속성만 갱신, **부팅 스크립트 재실행 안 함** → 여전히 미기동. `terraform apply -replace=aws_instance.backend` 로 교체해야 user-data 재실행.
  3. **docker on fresh ssh**: loadgen 새 ssh 세션은 ec2-user 의 docker 그룹이 미반영 → `docker run` permission denied(126). `sudo docker` 사용.
  4. **k6 컨테이너 파일 권한**: grafana/k6 가 uid 12345 비-root 라 `/home/ec2-user`(700) 통과 불가 → `stat /s/...: permission denied`. 스크립트를 `/tmp`(1777)에 두고 `-v /tmp:/s`.
- Prevention:
  - 부하 인프라 apply 전 **tfvars placeholder 잔존 검사**(`grep -E 'xxxxxxx|1.2.3.4|CHANGE_ME'`) — apply 성공 ≠ 동작.
  - GHCR 태그는 추측 말고 **실제 조회**: PAT 로 `GET https://ghcr.io/v2/<owner>/<repo>/tags/list` (Accept 헤더는 콤마 1줄로). README 태그 예시 신뢰 금지.
  - 8080 connection **refused**(빠른 실패)=SG 통과·앱 미기동(=user-data/이미지 문제), **timeout**(드롭)=SG/admin_cidr 문제 — 둘을 구분해 진단.
  - tfvars 의 image/PAT 변경 후엔 항상 `-replace=aws_instance.backend`.
- 측정 해석 교훈(재사용):
  - **빈 결과 쿼리가 느리면 = 공유 자원 큐잉**(풀/CPU), 개별 쿼리 최적화 아님. friendships(시드 0) p95 2.5s 가 결정적 단서였다.
  - **3티어 동시 관측 필수**: k6(클라) + CloudWatch backend CPU/CreditBalance + RDS CPU/DatabaseConnections. `DatabaseConnections` 가 풀 사이즈에 고정돼 있으면 풀이 동시성 캡.
  - **버스터블(t3) 인스턴스는 지속 부하 측정 대상으로 부적합** — CreditBalance 고갈 변수가 결과를 오염. 측정엔 c5 등 고정 성능.
- Updated:
  - [x] architecture/ADR — ADR-0011 작성
  - [x] 측정 산출물 — `docs/research/assets/measurement-trackC-iter1.md` (로컬)
  - [ ] README `infra/terraform-loadtest/README.md` 태그 안내 수정(`sha-<7>` → full SHA) — 후속
- Skip reason if not promoted: N/A

---

### 2026-06-10 — Colima 환경에서 Testcontainers 침묵 skip + JPA 정렬 getter 함정

- Trigger: production-risk (검증 신뢰성), audit-fixes 작업 중 발견
- Task/ADR: refactor/audit-fixes, EXEC_PLAN `docs/agent/plans/2026-06-10-audit-fixes.md`
- Failures & Root cause:
  1. **Testcontainers 침묵 skip**: 이 머신은 Docker Desktop 이 아니라 **Colima** 라 plain `./gradlew test` 에서 `disabledWithoutDocker` 가 컨테이너 테스트를 **조용히 skip** 한다. "BUILD SUCCESSFUL + N passed" 가 실DB 검증 없이 보일 수 있음 — 기존 `FriendshipMigrationTest` 도 그동안 skip 되고 있었다.
  2. **JPA 정렬 getter 함정**: `Match.quarters` 는 영속 필드가 아니라 정렬 getter (영속 필드는 `quarterWorkouts`). HQL `JOIN FETCH m.quarters` 는 경로 해석 실패 — fetch join 은 반드시 `m.quarterWorkouts`.
- Prevention:
  - 컨테이너 테스트 실행 시 env 필수: `DOCKER_HOST=unix:///Users/opix/.colima/default/docker.sock TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock`
  - 검증 단계에서 passed 수만 보지 말고 **skipped 카운트 0 확인** (`./gradlew test` 리포트의 skipped 컬럼).
  - HQL 작성 시 엔티티의 **영속 필드명** 확인 (getter 이름 ≠ 필드명일 수 있음).
- Updated:
  - [x] EXEC_PLAN 학습 기록 섹션
  - [ ] verify-and-block.sh 에 Colima env 주입 — 후속 후보
- Skip reason if not promoted: N/A

---

### 2026-06-23 — Sentry 연동: Spring Boot 4 starter 비호환 + Exception 핸들러 광역 캐치 회귀

- Trigger: self-heal (2회), feature/sentry-error-tracking
- Task/ADR: EXEC_PLAN `docs/agent/plans/2026-06-23-sentry-error-tracking.md`
- Failures & Root cause:
  1. **Sentry Spring Boot starter ↔ Spring Boot 4 비호환**: `io.sentry:sentry-spring-boot-starter-jakarta:8.16.0` 의 autoconfiguration 이 Spring Boot 4(Spring Framework 7)에서 **제거된 `org.springframework.boot.web.client.RestClientCustomizer`** 를 참조 → `SentryAutoConfiguration` 조건 평가 단계(nested class introspection)에서 `NoClassDefFoundError` → 컨텍스트 로드 실패. `@ConditionalOnClass` 로도 못 막음(이미 클래스 로딩 시도).
  2. **`@ExceptionHandler(Exception::class)` 광역 캐치가 Spring MVC 표준 예외를 500 으로 둔갑**: 미처리 예외 fallback 핸들러가 `NoResourceFoundException`(없는 경로 404)·`HttpRequestMethodNotSupportedException`(405) 까지 가로채 500 으로 변환 → `InvitationEndpointRemovalTest` 3건 회귀(404 기대→500). 에러 트래킹 관점에선 **없는 경로 요청이 죄다 5xx 로 Sentry 전송되는 노이즈 폭탄**.
- Prevention:
  - **Spring Boot 4 + 서드파티 Spring starter 는 호환성 선검증**: starter autoconfiguration 이 깨지면 **코어 의존성 + 수동 `@Configuration` init** 으로 폴백. 명시적 사용(여기선 `Sentry.captureException` 만)이면 starter 자동통합이 애초에 불필요한 경우가 많다. 컨텍스트 로드 smoke 테스트(`KicklogApplicationTests`)로 부팅 호환성을 반드시 확인.
  - **`@ExceptionHandler(Exception::class)` 는 반드시 Spring 표준 예외를 선분기**: 핸들러 내부에서 `if (e is org.springframework.web.ErrorResponse) → statusCode 보존` 후 나머지만 500 통일. 인터페이스 `ErrorResponse` 는 `@ExceptionHandler` 타입으로 못 쓰므로(Throwable 아님) instanceof 분기로 처리. 5xx 만 외부 전송.
  - 외부 전송(에러 트래킹)은 `runCatching` 으로 감싸 **정상 에러 응답 경로를 절대 막지 않게** 한다.
- Updated:
  - [x] EXEC_PLAN 학습 기록 섹션
  - [x] docs/agent/learning.md (본 항목)
  - [ ] code-reviewer 체크리스트: "`@ExceptionHandler(Exception)` 광역 캐치 시 Spring 표준 예외 선분기 확인" — 후속 후보
- Skip reason if not promoted: N/A

---

### 2026-07-11 — 스프린트 재설계: 비율 규칙의 분모 퇴화 + HealthKit read 권한 상태 조회 불가

- Trigger: missing-test (RED 1건) + review-major (M1), fix/sprint-metric-redesign
- Task/ADR: EXEC_PLAN `docs/agent/plans/2026-07-11-sprint-metric-redesign.md` / ADR-0012
- Failures & Root cause:
  1. **비율 기반 규칙의 분모 퇴화**: 심박 교차검증의 "세션 최고심박의 95% 도달이면 인정" 분기가 **심박이 완전히 평탄한 세션**에서 무의미 (세션 최고 == 평탄 수준 → 항상 통과 → 조깅 중 GPS 스파이크가 최고속도로 승격). 실측 픽스처(심박 변동 큼)만으론 절대 안 잡히고, 합성 unhappy 케이스가 적발.
  2. **HealthKit read 권한 상태는 조회 불가**: `authorizationStatus(for:)` 는 write(share) 상태만 반환 — read 허용 여부는 프라이버시 설계상 숨겨진다. "권한 확인 후 분기" 류 제안(리뷰 M1 원안)은 read 경로에선 동작하지 않음. 부재 원인(삭제 vs 권한 vs 동기화 지연)을 구분할 수 없으면 **영구 스킵은 형식적으로 확정 가능한 케이스(UUID 형식 불일치)로 한정**하고 나머지는 재시도.
- Prevention:
  - 비율/상대값 규칙 도입 시 **분모가 퇴화하는 케이스(평탄·0·단일값 데이터)를 합성 테스트로 반드시 커버**. 실측 픽스처는 happy 재현엔 강하지만 퇴화 입력엔 무력.
  - HealthKit 부재 판정 로직은 read 권한 조회가 불가함을 전제로 설계 (재시도 비용이 싸면 재시도가 기본값).
- Updated:
  - [x] EXEC_PLAN 학습 기록 섹션
  - [x] docs/agent/learning.md (본 항목)
  - [x] ADR-0012 D3/D5 본문
