# KickLog 백엔드 테스트 전략 (ATDD 1차)

> 본 문서는 KickLog **백엔드** 테스트의 **단일 진실 원천(SoT)** 이다.
> `.claude/agents/backend-test-writer.md`, `.claude/skills/orchestrator/SKILL.md` 의 EXEC_PLAN 템플릿, CLAUDE.md 의 TDD 원칙은 모두 본 문서를 참조한다.
> 본 문서와 충돌하는 규칙이 발견되면 본 문서가 우선한다.
>
> **iOS 는 본 하네스 대상 아님** — 사용자가 Xcode 에서 직접 작업하며, 자동 테스트·리뷰 강제 없음.

---

## 철학

**인수 테스트가 1차 전략이다.** 사용자 시점에서의 동작 보증이 회귀를 막는 가장 두꺼운 그물이다.
백엔드는 HTTP 단위(Cucumber + Testcontainers)로 인수를 정의한다.
통합·단위 테스트는 인수 테스트의 빈틈(복잡한 도메인 로직, 외부 의존 경계)을 메운다.

---

## 테스트 피라미드

| 계층 | 도구 | 작성 시점 |
|---|---|---|
| **인수** | Cucumber + Testcontainers (HTTP API 단위) | **항상** |
| **통합** | `@SpringBootTest` + Testcontainers (Service+Repository) | **항상** |
| **Web 계층** | `@WebMvcTest` (Controller + Validation 단독) | 필요 시 |
| **단위** | JUnit 5 + AssertJ + MockK (도메인 로직, ErrorCode, Validator) | 선택적 |

---

## ATDD 워크플로우 (TDD-first)

### Step 1: EXEC_PLAN 의 인수 시나리오 작성

`docs/agent/plans/YYYY-MM-DD-<slug>.md` 의 **"3. 테스트 케이스"** 섹션에
**Gherkin 시나리오** + **유스케이스/단위 테스트 케이스** 두 블록을 채운다.

```gherkin
# (3-A) 인수 시나리오 (Cucumber 변환 대상)
@auth @smoke
Feature: 카카오 로그인

  Scenario: 신규 사용자 가입
    Given 미가입 카카오 사용자가 있다
    When /auth/kakao 에 인가 코드로 로그인 요청한다
    Then 응답 상태 코드는 200 이다
    And 응답에 accessToken 이 포함된다
    And users 테이블에 1건이 생성된다

  @edge-case
  Scenario: 유효하지 않은 인가 코드
    Given 유효하지 않은 카카오 인가 코드
    When 로그인을 요청한다
    Then 응답 상태 코드는 401 이다
```

```text
# (3-B) 유스케이스/단위 테스트 케이스
- MatchService.upsertMatch: 같은 client_match_id 두 번 호출 → UPDATE only (count==1)
- KakaoCode.validate: 빈 문자열 / 공백 → InvalidCodeException
```

### Step 2: RED — 실패하는 테스트 작성

```bash
cd backend && ./gradlew test
```

새 시나리오·테스트 전부 실패 확인. "의도한 이유로 실패하는지" 반드시 확인 (컴파일 에러는 RED 가 아님).

### Step 3: GREEN — 최소 구현 → 통과

### Step 4: REFACTOR — 동작 유지, 중복·가독성 개선

---

## 시나리오 태그 전략

| 태그 | 목적 |
|---|---|
| `@smoke` | 핵심 경로, CI 모든 PR 에서 실행 |
| `@auth` | 인증 (Apple/Kakao/JWT) |
| `@user` | 사용자 (display_name, soft delete) |
| `@friend` | 친구 (friendship 권한, 정렬 pair) |
| `@match` | 경기 (PUT 멱등성, 쿼터 매핑) |
| `@place` | 장소 (카카오 프록시) |
| `@venue` | 경기장 |
| `@edge-case` | 경계 조건, 권한 위반, 외부 시스템 실패 |
| `@slow` | 30초+ 시나리오 (로컬 개발 시 제외) |

### 태그별 실행

```bash
./gradlew test -Dcucumber.filter.tags="@smoke"
./gradlew test -Dcucumber.filter.tags="@friend and not @slow"
```

---

## Happy / Unhappy 체크리스트

**EXEC_PLAN 의 "테스트 케이스" 섹션 작성 시 최소 1개씩 반드시 포함.** 빠지면 `enforce-plan.sh` 가 차단한다 (v1.1 강화 예정).

### Happy Path (최소 1)
- 정상 입력 → 기대 출력
- 경계값 성공 (예: display_name 30자)

### Unhappy Path (최소 1, 보통 여러 개)
- `null` / 빈 문자열 / 공백
- 범위 초과 / 음수 / 0
- 존재하지 않는 식별자 → 404
- 권한 없음 → 403 (friendship 미존재 등)
- 상태 전이 불가 (이미 삭제된 계정 재로그인 등)
- 외부 시스템 실패 (카카오 API 5xx, 타임아웃)

---

## Cucumber 인프라 컨벤션

> 첫 ATDD 도메인 작업 시 신설. 그 전까지는 본 섹션이 청사진.

### 위치

```
backend/src/test/kotlin/com/opixxx/kicklog/
├── support/
│   ├── IntegrationTestBase.kt        # @Testcontainers + @SpringBootTest 기반
│   ├── CucumberConfig.kt             # @CucumberContextConfiguration
│   ├── ScenarioContext.kt            # @ScenarioScope, Step 간 상태 공유
│   ├── TestApiClient.kt              # MockMvc 래핑 (get/post/put/patch/delete)
│   ├── TestResponse.kt               # ResponseEntity 래퍼
│   ├── stub/
│   │   ├── KakaoStubClient.kt        # 카카오 OAuth/Local API 스텁
│   │   └── AppleStubClient.kt        # Sign in with Apple 스텁
│   └── hooks/
│       └── ScenarioHooks.kt          # @Before/@After (인증 정리 등)
└── steps/                            # @Given/@When/@Then 정의
    ├── AuthStepDefinitions.kt
    ├── FriendStepDefinitions.kt
    └── ...
```

```
backend/src/test/resources/features/
├── auth/
├── user/
├── friend/
├── match/
├── place/
└── venue/
```

### Step Definition 규칙

- **기존 Step 최대한 재사용** — 새 Step 작성 전 grep 으로 확인:
  ```bash
  grep -rn "@Given\|@When\|@Then\|@And" backend/src/test/kotlin/com/opixxx/kicklog/steps/
  ```
- **새 Step 은 도메인 파일에 추가** (파일 신규 생성 최소화)
- 생성자 주입으로 `TestApiClient`, `ScenarioContext` 받기
- `context.setLastResponse(response)` → 다음 Then 에서 검증
- `context.put("createdMatchId", id)` → Step 간 상태 공유 (생성된 리소스 ID 컨벤션)
- 인증: `apiClient.authenticate(accessToken)` 한 번 호출, ScenarioHooks 가 시나리오 종료 시 정리

### Stub Client 컨벤션 (결정론)

- 같은 입력 → 같은 출력. `Random` 기반 분기 금지 (재시도 시 결과 뒤집힘 → 테스트 깨짐).
- 매직 코드 패턴:
  - `valid-code` → 정상 신규 가입
  - `valid-code-{userId}` → 기존 사용자 로그인
  - `invalid-code` → 401
  - `expired-code` → 401
- **싱글톤 Stub Bean 의 가변 컬렉션 금지** — `@Scope("prototype")` 또는 `@BeforeEach reset()`. 누적 상태 공유는 플래키 테스트의 근원.

---

## 통합/단위 테스트 컨벤션

### 통합 테스트 (Service + Repository)

```kotlin
@Testcontainers
@SpringBootTest
abstract class IntegrationTestBase {
    companion object {
        @Container
        @JvmStatic
        val postgres = PostgreSQLContainer<Nothing>("postgres:16-alpine").apply {
            withDatabaseName("kicklog_test")
            withUsername("test")
            withPassword("test")
        }

        @JvmStatic
        @DynamicPropertySource
        fun overrideProps(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url") { postgres.jdbcUrl }
            registry.add("spring.datasource.username") { postgres.username }
            registry.add("spring.datasource.password") { postgres.password }
        }
    }
}
```

- `@Transactional` 로 DB 롤백 (테스트 격리)
- Repository 테스트는 **실제 PostgreSQL** (`@DataJpaTest` + Testcontainers). H2 금지 — Postgres 와 JSON/배열/시퀀스 동작 차이.
- N+1, 인덱스, Fetch 전략 검증 — 쿼리 로그 활성화 (`spring.jpa.show-sql=true` 테스트 프로파일)

### 단위 테스트 (도메인 모델, Validator)

- 스프링 컨텍스트 불필요. 순수 JUnit + AssertJ.
- < 100ms / 테스트.
- 도메인 검증 로직(`Match.create` 의 4쿼터 초과 등), 복잡한 계산(스프린트 카운트), 상태 전이가 주력.

### MockK 사용 기준

```kotlin
val kakaoClient = mockk<KakaoLocalClient>()
every { kakaoClient.searchKeyword(any(), any(), any(), any()) } returns SearchResult(...)
verify { kakaoClient.searchKeyword("○○공원", any(), any(), any()) }
```

- **외부 API (카카오, Apple)** 는 Mock 또는 WireMock
- **Repository 는 Mock 금지** — Testcontainers 실제 DB
- **도메인 객체 자체를 Mock 하지 않음** — Mock 한 도메인은 허수 테스트

### 예외 검증

`assertThatThrownBy` 로 **3종 검증** (타입 + 메시지 + root cause):

```kotlin
assertThatThrownBy { service.create(cmd) }
    .isInstanceOf(DuplicateEmailException::class.java)
    .hasMessageContaining("이미 사용 중")
    .hasRootCauseInstanceOf(DataIntegrityViolationException::class.java)
```

ErrorCode 검증은 예외의 `status` / `message` 필드 직접 비교:

```kotlin
assertThat(thrown.status).isEqualTo(ErrorCode.NOT_FOUND_USER.status)
```

### 네이밍 규칙

| 대상 | 패턴 |
|---|---|
| 테스트 클래스 | `{ClassName}Test` (단위), `{ClassName}IntegrationTest` (통합) |
| 테스트 메서드 | Kotlin backtick 한글 — `` `친구_데이터_조회 - friendship 없으면 UnauthorizedFriendshipException`() `` |
| `@DisplayName` | "기능 — 조건 → 결과" 형식 (예: "쇼케이스 생성 — 빈 제목 → InvalidShowcaseException") |

---

## 테스트 데이터 관리

### 고유 식별자 (충돌 방지)

```kotlin
val nickname = "테스터_${System.currentTimeMillis()}"
val providerUserKey = "kakao-${UUID.randomUUID().toString().substring(0, 8)}"
```

### 시간 의존 금지

```kotlin
// BAD — 자정 근처에서 깨짐
val endTime = LocalTime.now().plusHours(1)

// GOOD — 고정값
val endTime = LocalTime.of(23, 59)

// GOOD — Clock 주입
val match = MatchService(clock = Clock.fixed(Instant.parse("2026-05-21T10:00:00Z"), ZoneOffset.UTC))
```

`Instant.now()`, `LocalDate.now()` 같은 호출이 production 코드에 있으면 **Clock 추상화** 후 테스트에서 주입.

### Fixture 빌더

도메인 객체 생성을 반복하지 말고 fixture 클래스/DSL:

```kotlin
object MatchFixture {
    fun default(userId: Long = 1L, quarterCount: Int = 4): Match = Match(
        userId = userId,
        clientMatchId = UUID.randomUUID(),
        playedAt = Instant.parse("2026-05-21T10:00:00Z"),
        quarters = (1..quarterCount).map { QuarterFixture.default(it) }
    )
}
```

---

## 도메인별 우선순위

| 도메인 | 우선순위 | 인수 시나리오 최소 개수 |
|---|---|---|
| `auth/` (Sign in with Apple/Kakao, JWT) | **Critical** — 보안 | Happy 2, Unhappy 3 |
| `friend/` (friendship 권한, pair UNIQUE) | **Critical** — 권한 | Happy 2, Unhappy 3 |
| `match/` (PUT 멱등성, 쿼터 매핑) | High | Happy 1, Unhappy 2 |
| `place/` (카카오 프록시) | High | Happy 1, Unhappy 2 |
| `venue/` | Medium | Happy 1, Unhappy 1 |
| `user/` (display_name 검색, soft delete) | Medium | Happy 1, Unhappy 2 |
| `common/exception/` | Low | 단위 테스트만 |

---

## 금지 사항

- ❌ `@Disabled`, `Assumptions.assumeTrue` 로 실패 테스트 회피
- ❌ `-DskipTests`, `--no-verify` 로 검증 우회
- ❌ Happy Path 만 있는 스위트 (Unhappy 누락)
- ❌ Mock over-use — Repository / 도메인 객체 Mock 금지
- ❌ 테스트 순서 의존 (`@TestMethodOrder` 남용)
- ❌ 공유 상태 (싱글톤 Stub 의 누적 컬렉션 등)
- ❌ 약한 assertion (`isNotNull`, `isNotEmpty` 만으로 끝) — 호출 자체 / 구체 값을 검증
- ❌ ATDD 시나리오 없이 새 API endpoint 추가 (30줄 이상 변경 시)

---

## 30줄 미만 면제 규칙

`CLAUDE.md` 의 "30줄 미만은 EXEC_PLAN + TDD 면제" 가 그대로 적용된다. 단,

- **새 API endpoint 추가** 는 줄 수와 무관하게 인수 시나리오 1개 이상 필수
- **DB 마이그레이션 동반 변경** 은 줄 수와 무관하게 통합 테스트 1개 이상 필수
- **친구 권한 검증 경로** 변경은 줄 수와 무관하게 Unhappy 경로(403) 시나리오 필수

---

## 커버리지

라인 커버리지보다 **시나리오 커버리지** 를 1차 지표로 삼는다. (1인 사이드 + ATDD 중심)

```bash
# 시나리오 수
grep -rc "Scenario:" backend/src/test/resources/features/

# 도메인별 시나리오 수
grep -rl "Scenario:" backend/src/test/resources/features/ | xargs -I {} sh -c 'echo {} && grep -c "Scenario:" {}'
```

라인 커버리지 게이트는 도입하되 수치는 도메인 안정화 후 측정해서 정한다 (v1.1).

---

## CI/CD

```yaml
# GitHub Actions
- name: 백엔드 빌드+테스트
  working-directory: backend
  run: ./gradlew check
```

`./gradlew check` 가 컴파일 + JUnit + Cucumber + (도입 후) JaCoCo 게이트를 한 번에 수행.

---

## PR 체크리스트

PR 본문에 다음 체크박스 자동 추가 (`/pr-guide` 스킬):

- [ ] 신규 기능에 Gherkin 인수 시나리오가 있다
- [ ] Happy Path + Unhappy Path 각 1개 이상
- [ ] 기존 Step / Mock / Fixture 를 가능한 재사용했다
- [ ] 로컬 테스트 통과 (`./gradlew test`)
- [ ] 시간 의존 로직 없음 (`now()` 직접 호출 0건)
- [ ] 적절한 태그 적용 (`@smoke`, `@<도메인>`)

---

## 관련 자산

- 백엔드 에이전트: `.claude/agents/backend-test-writer.md`
- EXEC_PLAN 템플릿: `.claude/skills/orchestrator/SKILL.md` "1. EXEC_PLAN 생성"
- 백엔드 컨벤션: `.claude/skills/coding-conventions/SKILL.md`
- ADR — 데이터 모델 / 권한: `docs/adr/0003-data-model-and-api.md`
