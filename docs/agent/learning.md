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

### 2026-08-19 — 응답 시간 포맷 계약 위반: 신규 사용자 로그인 전면 실패 (운영 장애)

- Trigger: production-risk, fix/instant-seconds-serialization
- Task/ADR: EXEC_PLAN `docs/agent/plans/2026-08-19-instant-seconds-serialization.md`
- Failures & Root cause:
  1. **Jackson 의 비결정적 시간 출력**: Jackson 3 는 `Instant` 의 나노초가 0 이면 소수부를 생략하고, 0 이 아니면 붙인다 (`2026-08-19T09:38:29.392099Z`). 같은 엔드포인트가 **값에 따라 다른 포맷**을 내보내는 상태였고, 이는 `docs/spec/api-spec.md` 가 규정한 계약(`2026-05-21T10:00:00Z`) 위반이었다.
  2. **명세가 예시로만 존재**: 계약이 예시 문자열로만 적혀 있고 **테스트로 고정되지 않아**, 구현이 계약을 어겨도 아무도 못 잡았다.
  3. **최신 OS 에서만 테스트**: iOS 18 의 `JSONDecoder.iso8601` 은 소수부를 거부하지만, iOS 26 의 새 swift-foundation 파서는 허용한다. 개발자 기기(iOS 26)에서는 증상이 아예 안 나타나 **신규 사용자 로그인이 전면 실패하는 동안에도 정상으로 보였다**. 이 맥에는 최소 지원 버전(iOS 18.0) 시뮬레이터 런타임 자체가 없었다.
  4. **증상이 기존 사용자에게 안 보임**: 지뢰가 로그인 응답(`user.createdAt`)에만 있고 `/auth/refresh` 응답에는 날짜 필드가 없어, 이미 로그인한 사용자는 영원히 안 밟는다. 그래서 "나는 잘 되는데 그 사람만" 으로 보였다.
- 진단에 결정적이었던 것:
  - **nginx 액세스 로그의 User-Agent Darwin 버전** — `Darwin/24.6.0`(iOS 18.6) 기기만 signin 을 4회 연속 재시도하고 이후 `/auth/refresh` 가 한 건도 없었다(= 토큰 저장 실패). `Darwin/25.x`(iOS 26) 는 signin 1회 후 refresh 로 이어짐(= 정상). 서버는 전부 200 을 반환했으므로 **서버 정상 + 클라이언트 파싱 실패**가 로그만으로 확정됐다.
  - 앱 에러 문구가 `decodingFailed` 계열인지(2xx 인데 파싱 실패) `server` 계열인지 구분한 것.
- Prevention:
  - **외부 계약(응답 포맷)은 예시가 아니라 테스트로 고정한다.** mapper 레벨 + **HTTP 응답 경계(MockMvc)** 양쪽에서. 경계 테스트는 "설정을 끄면 그 테스트만 실패하는가"로 실효를 검증한다.
  - **직렬화는 엄격하게, 역직렬화는 관대하게.** 이미 배포된 클라이언트를 깨지 않으려면 입력은 넓게 받아야 한다.
  - **`Instant.toString()` 으로 미리 문자열화하지 말 것** — 전역 시리얼라이저를 조용히 우회한다 (`HealthCheckController` 가 실제로 그랬다).
  - **클라이언트 최소 지원 버전에서 최소 1회 검증한다.** 최신 OS 의 관대한 파서가 계약 위반을 가려준다.
  - 서버 수정은 앱 배포 없이 즉시 반영되므로, **클라이언트 호환 장애는 서버에서 먼저 지혈**하고 클라이언트 근본 수정을 뒤따르게 한다.
- Updated:
  - [x] EXEC_PLAN 학습 기록 섹션
  - [x] docs/agent/learning.md (본 항목)
  - [x] docs/spec/api-spec.md · docs/architecture/api-conventions.md — "소수부 금지" 를 문장으로 명시
  - [ ] iOS `APIClient` 디코더에 소수부 폴백 추가 — 후속 (2026-08-20 예정)
  - [ ] iOS 18 시뮬레이터 런타임 설치 후 최소 지원 버전 스모크 — 후속 후보
  - [ ] `*Response` 의 `java.time` 필드 타입을 검사하는 가드 테스트 — 후속 후보 (code-reviewer 제안)
- Skip reason if not promoted: N/A
