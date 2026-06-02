---
name: project-acceptance-test-convention
description: KickLog 백엔드의 실제 인수 테스트는 Cucumber 가 아니라 MockMvc 기반 *AcceptanceTest.kt 다
metadata:
  type: project
---

KickLog 백엔드의 인수 테스트는 **Cucumber 가 아니다**. `docs/spec/test-strategy.md` 의 "Cucumber 인프라 컨벤션" 절은 도입되지 않은 **청사진**일 뿐이다 (build.gradle.kts 에 cucumber 의존성 없음, `.feature`/`steps/`/`support/` 디렉터리 0개).

**실제 컨벤션** (예: `match/MatchAcceptanceTest.kt`, `friend/FriendshipAcceptanceTest.kt`):
- `@SpringBootTest @AutoConfigureMockMvc @ActiveProfiles("test")` + `MockMvc` DSL (`mockMvc.get/post/put`).
- 인증은 `JwtTokenProvider.createAccessToken(userId)` 로 직접 토큰 발급 후 `Authorization: Bearer` 헤더.
- 메서드명은 backtick 한글. `jsonPath` 로 응답 검증.

**DB 셋업**:
- 기본 단위/슬라이스/인수 테스트: `application-test.yml` 의 **H2(PostgreSQL 모드)**, `ddl-auto: create-drop`, flyway off.
- 실제 PostgreSQL 검증(마이그레이션·raw SQL): Testcontainers — `FriendshipMigrationTest` 패턴 (`@Testcontainers(disabledWithoutDocker=true)` + `@DynamicPropertySource` + `KickLogPostgresContainer`).
- `loadtest`/`prod` 프로파일은 H2 test yml 을 안 타고 base `application.yml` 의 PostgreSQL + flyway validate 를 상속 → 이 프로파일로 `@SpringBootTest` 하려면 **Testcontainers 가 필수** (안 그러면 localhost:5432 접속 실패로 컨텍스트 로드 자체가 깨짐 = 잘못된 RED).

**Why:** 1인 사이드 + ATDD 중심으로 시작했으나 Cucumber 는 미채택. SoT 와 실제 코드가 충돌하면 **실제 코드 컨벤션을 따른다** (작업 지시도 "기존 베이스클래스·태그를 따르라").

**How to apply:** 새 인수 테스트는 `*AcceptanceTest.kt` + MockMvc 로 작성. `.feature` 파일 만들지 말 것. loadtest/prod 프로파일 SpringBootTest 는 Testcontainers 동봉.

관련: [[project-loadtest-harness-schema]]
