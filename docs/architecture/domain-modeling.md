# KickLog 도메인 모델링 정책 — 3-tier + DDD-lite

> KickLog 는 단순 3-tier 구조(Controller / Service / Repository) 를 유지하면서도 **DDD 의 모델링 측면**(Aggregate, VO, Ubiquitous Language, Domain Service)을 적용한다.
> 본 문서는 그 정책의 SoT.

---

## 한 줄 요약

**구조는 3-tier, 모델링은 DDD-lite.** Rich Aggregate + Value Object + Ubiquitous Language 까지는 도입하고, Domain Event / CQRS / 헥사고날은 v1.1+ 로 보류.

---

## 두 차원 분리 — 흔한 오해

| 차원 | 무엇을 결정 | KickLog 선택 |
|---|---|---|
| **구조 패턴** | Controller / Service / Repository 책임 배치, 의존 방향 | **3-tier** (ADR-0003) |
| **모델링 방법론** | 도메인 로직을 어디에 어떻게 표현 | **DDD-lite** (본 문서) |

> "DDD 하려면 헥사고날 필수" 는 잘못된 통념이다.
> DDD 는 *모델링 방법론* 이고, 헥사고날 / 3-tier 는 *구조 패턴* 이다. 자유롭게 조합 가능.

ADR-0003 Consequences 의 "헥사고날·DDD 없이 단순 Spring 레이어로 충분" 은 **헥사고날 패키지 분리 + Domain Event 등 무거운 패키지** 를 거부한 것이지, *모델링 측면의 DDD* 를 거부한 것은 아니다.

---

## DDD 요소별 도입 정책

| 요소 | 도입 | 이유 |
|---|---|---|
| **Ubiquitous Language** | ✅ 필수 | 비용 0, 효과 큼. 코드·DB·DTO·문서 용어 통일 |
| **Aggregate (Rich Model)** | ✅ 권장 | Entity 안에 비즈니스 메서드. Service 비대화 방지 |
| **Value Object** | ✅ 권장 | Primitive Obsession 회피, 검증 응집 |
| **Repository (DDD)** | ✅ 적용 | Aggregate Root 단위. `MatchRepository` O, `QuarterWorkoutRepository` X |
| **Domain Service** | ✅ 적용 | Aggregate 둘 이상 걸친 로직 (`FriendshipAuthorizer`) |
| **Bounded Context** | ✅ 적용 | 도메인 패키지 = BC. `auth/`, `friend/`, `match/` 등 |
| **Factory** | ✅ 권장 | 정적 팩토리(`Match.create(...)`)에 검증 응집, JPA 기본 생성자 우회 |
| **Anti-Corruption Layer** | ✅ 적용 | 외부 응답을 우리 도메인으로 변환 (`KakaoLocalClient`) |
| **Domain Event** | ⏸️ v1.1 | 트랜잭션 외 처리 복잡, MVP 효과 작음 |
| **CQRS** | ⏸️ v1.1+ | 읽기/쓰기 분리, MVP 에 over-engineering |
| **Saga / Process Manager** | ❌ | 단일 서비스에 불필요 |
| **헥사고날 Port/Adapter** | ❌ | ADR-0003 결정 — 단순 레이어드 유지 |

---

## Anemic vs Rich — 같은 3-tier, 다른 모델링

### Anemic (안티패턴)

```kotlin
@Entity
class Match {
    var totalDistanceM: Int = 0
    var quarters: MutableList<QuarterWorkout> = mutableListOf()
    // 전부 var + getter/setter
}

@Service
class MatchService(private val repo: MatchRepository) {
    @Transactional
    fun addQuarter(matchId: Long, q: QuarterWorkout) {
        val match = repo.findByIdOrThrow(matchId)
        if (match.quarters.size >= 4) throw MatchQuarterOverflowException()   // 불변식이 Service
        match.quarters.add(q)
        match.totalDistanceM = match.quarters.sumOf { it.distanceM }          // 재계산도 Service
        repo.save(match)
    }
}
```

**문제:**
- Entity 가 데이터 가방. 같은 검증·계산이 여러 Service 에 중복되기 쉬움.
- Entity 단독 테스트 불가, 항상 Service · DB 통해야 함.
- 외부에서 `match.totalDistanceM = -100` 같은 invalid 상태 만들 수 있음.

### Rich (3-tier + DDD-lite)

```kotlin
@Entity
class Match private constructor(
    @Id @GeneratedValue val id: Long? = null,
    val userId: Long,
    val clientMatchId: UUID,
    val playedAt: Instant,
    @Embedded var headline: HeadlineMetrics,                                  // VO
    @OneToMany(mappedBy = "match", cascade = [CascadeType.ALL])
    private val _quarters: MutableList<QuarterWorkout> = mutableListOf(),
) {
    val quarters: List<QuarterWorkout> get() = _quarters.toList()             // 외부엔 immutable

    companion object {
        fun create(userId: Long, clientMatchId: UUID, playedAt: Instant): Match {
            // 검증 응집 — 모든 Match 는 이 팩토리를 통과
            return Match(
                userId = userId,
                clientMatchId = clientMatchId,
                playedAt = playedAt,
                headline = HeadlineMetrics.zero(),
            )
        }
    }

    fun addQuarter(q: QuarterWorkout) {                                       // 비즈니스 메서드
        check(_quarters.size < 4) { throw MatchQuarterOverflowException() }   // 불변식이 Aggregate
        _quarters.add(q)
        recalculateHeadline()
    }

    private fun recalculateHeadline() {
        headline = HeadlineMetrics(
            totalDistanceM = _quarters.sumOf { it.distanceM },
            maxSpeedKmh    = _quarters.maxOf { it.avgSpeedKmh },
            sprintCount    = _quarters.sumOf { it.sprintCount },
            avgHeartRate   = _quarters.weightedAvgHeartRate(),
        )
    }
}

@Embeddable
data class HeadlineMetrics(                                                   // Value Object
    val totalDistanceM: Int,
    val maxSpeedKmh: BigDecimal,
    val sprintCount: Int,
    val avgHeartRate: Int,
) {
    init {
        require(totalDistanceM >= 0) { "총 거리는 음수일 수 없습니다" }
        require(sprintCount >= 0)    { "스프린트 횟수는 음수일 수 없습니다" }
        require(avgHeartRate in 0..250)
    }
    companion object { fun zero() = HeadlineMetrics(0, BigDecimal.ZERO, 0, 0) }
}

@Service
class MatchService(private val repo: MatchRepository) {
    @Transactional
    fun addQuarter(matchId: Long, q: QuarterWorkout) {
        val match = repo.findByIdOrThrow(matchId)
        match.addQuarter(q)                                                   // 도메인이 책임
        repo.save(match)
    }
}
```

**같은 3-tier 패키지 구조다.** Controller / Service / Repository / Entity 위치 동일. 바뀐 건:
- Entity 가 자기 상태 변화에 책임 — **Aggregate Root**
- 불변식이 Entity 안 (`check` / `require`)
- VO 가 Primitive 묶음을 대체 — 검증 응집
- Service 는 트랜잭션·오케스트레이션만, 비즈니스 로직 X

---

## 1. Ubiquitous Language

**가장 먼저 적용해야 할 DDD 요소.** 코드 한 줄 안 바꾸고도 시작 가능.

### 규칙

- 같은 개념은 코드 · DB · DTO · 문서 · 대화에서 **하나의 단어**로 부른다
- 모호한 범용어 (`process`, `handle`, `execute`, `data`, `info`) 회피 — 도메인 어휘 우선

### KickLog 핵심 어휘 (예시)

| 도메인 | 영어 | 한국어 | 동의어 사용 금지 |
|---|---|---|---|
| 사용자 식별 표시 | `displayName` | 표시 이름 | name, nickname |
| 친구 관계 | `Friendship` | 친구 관계 | friend, buddy |
| 친구 초대 링크 | `FriendInvitation` (`token` 8자 base62) | 초대 링크 | invite, link |
| 경기 단위 | `Match` (`clientMatchId` UUID) | 경기 | game, session |
| 쿼터 워크아웃 | `QuarterWorkout` (`quarterNo` 1~4) | 쿼터 | period, set |
| 운동장 | `Venue` | 운동장 | place, ground, field |
| 카카오 검색 결과 | `Place` | 장소 | location, poi |
| OAuth 신원 | `OAuthIdentity` (`provider` apple/kakao) | OAuth 신원 | identity, account |

→ ADR-0003 의 결정 어휘를 그대로 따른다. 새 개념 등장 시 **ADR 갱신 → 코드 반영** 순.

### 코드에서 강제

- 패키지명 = 도메인 단어 (`match/`, `friend/`)
- 클래스명 = Ubiquitous Language (`MatchRepository`, `FriendshipAuthorizer`)
- DB 컬럼명 = snake_case 동일 어휘 (`client_match_id`, `display_name`)
- 변수명 도 일관 (`displayName` X, `nickname` X — 항상 `displayName`)

### code-reviewer 가 잡을 패턴
- 같은 개념을 다른 단어로 부르는 경우 (`name` vs `displayName`)
- 범용어 메서드명 (`processMatch()`, `handleFriendship()`)

---

## 2. Aggregate

### 정의 (KickLog 기준)

**일관성 경계 + 트랜잭션 경계 + Repository 단위.**
한 Aggregate 안의 모든 객체는 **Aggregate Root 를 통해서만** 변경된다.

### KickLog Aggregate 후보

| Aggregate Root | 내부 객체 | 경계 근거 |
|---|---|---|
| `Match` | `QuarterWorkout` 1~4 | 같은 트랜잭션에 함께 변경 (PUT 멱등) |
| `Friendship` | (혼자) | 정렬 pair 1 row, 외부 객체 없음 |
| `FriendInvitation` | (혼자) | 단일 row, `useCount` 만 증감 |
| `User` | (혼자) — `OAuthIdentity` 는 별도 Aggregate | 둘은 독립적으로 추가/삭제 가능 (provider 연결·해제) |
| `OAuthIdentity` | (혼자) | User 와 다른 라이프사이클 |
| `Venue` | (혼자) | 단일 row |

### 규칙

1. **Aggregate Root 만 Repository 가짐**
   - ✅ `MatchRepository`, `FriendshipRepository`
   - ❌ `QuarterWorkoutRepository` 단독 X (Match 를 통해 접근)

2. **외부에서 Aggregate 내부 객체 직접 변경 금지**
   - ❌ `match.quarters.add(q)` (외부에서 list 변경)
   - ✅ `match.addQuarter(q)` (Aggregate 메서드 경유)

3. **Aggregate 메서드는 비즈니스 어휘**
   - ✅ `match.addQuarter(q)`, `friendship.accept()`, `user.softDelete()`, `invitation.use()`
   - ❌ `match.setQuarters(...)`, `friendship.setStatus("accepted")`

4. **불변식은 Aggregate 안에서 강제**
   - 예: `Match` 는 쿼터 최대 4개 → `addQuarter` 안에서 `check(_quarters.size < 4)`
   - 예: `Friendship` 은 `user_low_id < user_high_id` → 팩토리에서 `LEAST/GREATEST` 정렬

5. **한 트랜잭션에 한 Aggregate** (strict DDD)
   - KickLog 는 strict 까지 가지 않음. Service 가 Aggregate 2~3개 조율은 허용.
   - 단 **friendship 권한 검증** 같이 BC 경계 넘으면 Domain Service 사용 (`FriendshipAuthorizer`)

### JPA + Aggregate 함정과 회피

| 함정 | 회피 |
|---|---|
| JPA 가 기본 생성자 요구 | `protected constructor()` + 정적 팩토리 `companion object { fun create() }` |
| `val` 로 선언 시 JPA reflection 문제 | Kotlin `plugin.spring` + `plugin.jpa` Gradle 플러그인 사용 (`val` 도 reflection 가능하게) |
| `@OneToMany` mutable list 외부 노출 | private `_quarters` + public `quarters.get() = _quarters.toList()` |
| Cascade 누락 | Aggregate Root 에 `@OneToMany(cascade = [CascadeType.ALL], orphanRemoval = true)` |

---

## 3. Value Object

### 정의

**불변 + 동등성은 값으로 판단 + 검증 응집.** Primitive Obsession 회피용.

### KickLog VO 후보

| VO | 대체할 Primitive | 검증 |
|---|---|---|
| `HeadlineMetrics` | 4 Int 묶음 | 음수 금지, 심박 범위 |
| `DisplayName` | `String` | 1~50자, 공백 trim |
| `ShortCode` (초대 token) | `String` | 정확히 8자, base62 |
| `GeoPoint` | `lat: BigDecimal, lng: BigDecimal` | 위도 -90~90, 경도 -180~180 |
| `Email` | `String` | RFC 형식 |
| `ProviderUserKey` | `String` | provider+id 결합 |

### JPA 와의 통합

```kotlin
@Embeddable
data class DisplayName(val value: String) {
    init {
        require(value.isNotBlank()) { "표시 이름은 공백일 수 없습니다" }
        require(value.length in 1..50) { "표시 이름은 1~50자여야 합니다" }
    }
}

@Entity
class User(
    @Id @GeneratedValue val id: Long? = null,
    @Embedded var displayName: DisplayName,
    // ...
)
```

### VO 적용 기준

| 적용 ✅ | 적용 X |
|---|---|
| 검증 규칙 있음 (음수 금지, 범위 제한) | 단순 식별자 (`userId: Long`, `matchId: Long`) |
| 같은 검증이 여러 곳에서 반복 | 인덱스·크기 (`size: Int`) |
| 단위/의미 있음 (가격·횟수·거리) | 한 번 쓰고 버리는 임시 값 |
| 함께 다니는 primitive 묶음 (lat+lng) | — |

---

## 4. Domain Service

### 정의

**Aggregate 둘 이상에 걸친 로직, 또는 어느 Aggregate 에도 자연스럽게 속하지 않는 도메인 로직.**

### KickLog 후보

| Domain Service | 책임 | 위치 |
|---|---|---|
| `FriendshipAuthorizer` | viewer 가 target 의 데이터를 볼 권한 있는지 (`Friendship` 조회 + `User.deletedAt` 확인) | `friend/service/` |
| `MatchUpserter` (옵션) | PUT 멱등 처리: 기존 Match 조회 → update 또는 신규 create | `match/service/` (Service 안 private 메서드로도 충분) |
| `ShortCodeGenerator` | base62 8자 + 중복 회피 (DB 조회) | `friend/service/` 또는 `common/util/` |

### Application Service (3-tier 의 Service) 와 구분

- **Application Service** (`MatchService`): 트랜잭션 경계, 외부 의존 조율, DTO ↔ Entity 변환
- **Domain Service**: 도메인 어휘로 표현된 비즈니스 규칙, **상태 없음** (`@Service` 일 수도 있지만 의미가 다름)

실무 차이는 미세함. **이름·책임**만 명확히 하면 둘 다 `@Service` 어노테이션 사용해도 OK.

---

## 5. Anti-Corruption Layer

### 정의

**외부 시스템 응답을 우리 도메인 모델로 변환하는 매퍼.** 외부 모델 변경이 우리 도메인에 새지 않게.

### KickLog 적용

| 외부 | ACL | 위치 |
|---|---|---|
| Kakao Local API (`place_name`, `road_address_name` 등) | `KakaoLocalClient` 가 `Place` (우리 도메인) 로 변환 | `place/service/KakaoLocalClient.kt` |
| Apple JWKS 응답 | `AppleIdentityVerifier` 가 `AppleIdentity` (우리 도메인) 로 변환 | `auth/service/AppleIdentityVerifier.kt` |
| Kakao `/v2/user/me` 응답 | `KakaoOAuthClient` 가 `KakaoUserInfo` 로 변환 | `auth/service/KakaoOAuthClient.kt` |

### 규칙

- 외부 응답 JSON 키 (`place_name`) 를 우리 도메인 (`name`) 까지 흘리지 않는다
- Service 는 외부 client 호출 시 **우리 도메인 객체만** 받음
- 외부 응답 형식이 바뀌면 ACL 만 수정, 도메인은 그대로

---

## 6. Bounded Context

### KickLog BC 매핑

| BC | 패키지 | Aggregate |
|---|---|---|
| **Identity** | `auth/`, `user/` | `User`, `OAuthIdentity`, `RefreshToken` |
| **Friendship** | `friend/` | `Friendship`, `FriendInvitation` |
| **Match** | `match/` | `Match` (with `QuarterWorkout`) |
| **Place** | `place/`, `venue/` | `Venue` (`Place` 는 외부 데이터, Aggregate 아님) |
| **Statistics** | `stat/` | Aggregate 없음 (read-only 집계) |

### BC 간 통신 규칙

- BC 끼리는 **Application Service** 를 통해서만 (Repository 직접 X)
- Friendship → User 데이터 필요 시 `UserService.findById(...)` 호출
- BC 사이 객체 전달은 **DTO / VO 만** (Entity 직접 X)

### 위반 시 code-reviewer Critical
- `auth/service/AuthService` 가 `friend/repository/FriendshipRepository` 직접 import
- `match/service/MatchService` 가 `user/entity/User` 의 internal 필드 접근

---

## 7. 도입 단계 (점진적)

| 단계 | 도입 | 우선순위 | 효과 |
|---|---|---|---|
| **1** | Ubiquitous Language 정착 (코드·DB·DTO·문서 용어 통일) | **첫 도메인 시작 전 필수** | 큼 |
| **2** | Rich Aggregate — Entity 안에 비즈니스 메서드 · 정적 팩토리 · 불변식 | **첫 도메인부터** | 큼 |
| **3** | Value Object — `DisplayName`, `HeadlineMetrics` 등 검증 응집 | **두 번째 Aggregate 부터** (한 번 쓰고 버리는 VO 는 굳이 X) | 큼 |
| **4** | Domain Service — `FriendshipAuthorizer` 등 BC 경계 횡단 | **friendship 도메인 시작 시** | 중 |
| **5** | Domain Event | v1.1 | 중 |
| **6** | CQRS | v1.1+ | 작음 |
| **7** | 헥사고날 Port/Adapter | 도입 안 함 (ADR-0003) | — |

**1~4 가 MVP 범위.** 5~6 는 트래픽·복잡도가 자라면 검토.

---

## 8. 새 Aggregate 추가 시 체크리스트

backend-test-writer / code-reviewer 가 이 항목들을 본다:

- [ ] 정적 팩토리 메서드로만 생성 (`Match.create(...)`), public 생성자 X
- [ ] 모든 불변식이 팩토리 또는 비즈니스 메서드 안에 (`check` / `require`)
- [ ] 외부에서 mutable 컬렉션 직접 변경 불가 (private `_xxx` + public immutable getter)
- [ ] Aggregate Root 만 Repository 보유 (`@Entity` 자식은 Repository X)
- [ ] 비즈니스 메서드 이름이 도메인 어휘 (`addQuarter`, `accept`, `softDelete` — `setXxx` X)
- [ ] Primitive 묶음 / 검증 있는 값은 `@Embeddable` VO 로
- [ ] BC 외부에서 본 Aggregate 의 internal 필드 접근 0건
- [ ] 단위 테스트로 Aggregate 단독 검증 가능 (Spring 컨텍스트·DB 없이)
- [ ] Service 는 트랜잭션·오케스트레이션만, 비즈니스 로직 0

---

## 9. 안티패턴 — 자주 보이는 실수

### Anemic Domain Model
- ❌ Entity 가 getter/setter 만, 로직은 Service
- ✅ Entity 안에 비즈니스 메서드 · 불변식

### Setter 노출
- ❌ `match.totalDistanceM = 1000`
- ✅ `match.addQuarter(...)` → 내부에서 재계산

### Repository 남발
- ❌ `QuarterWorkoutRepository.findByMatchId(...)` 를 Service 가 직접 호출
- ✅ `MatchRepository.findByIdOrThrow(matchId).quarters` (Aggregate 통해)

### 트랜잭션 외 Aggregate 변경
- ❌ Service 메서드 밖에서 `entity.someMutation()` 후 미저장
- ✅ Service `@Transactional` 안에서만 변경

### 도메인 로직이 Controller 에
- ❌ Controller 가 `if (request.quarters.size > 4) throw ...`
- ✅ Aggregate 팩토리 / 메서드가 검증

### 외부 DTO 가 도메인까지 침투
- ❌ Service 가 `KakaoPlaceSearchDto` 받아서 처리
- ✅ ACL 에서 `Place` 로 변환 후 전달

---

## 관련 자산

- 구조 패턴: [`overview.md`](./overview.md) — 패키지·레이어·DTO 흐름
- 인증 흐름: [`auth.md`](./auth.md)
- API 규약 · ErrorCode: [`api-conventions.md`](./api-conventions.md)
- 결정 근거: [`docs/adr/0003-data-model-and-api.md`](../adr/0003-data-model-and-api.md)
- 테스트 전략: [`docs/spec/test-strategy.md`](../spec/test-strategy.md)
- 코딩 컨벤션: [`.claude/skills/coding-conventions/SKILL.md`](../../.claude/skills/coding-conventions/SKILL.md)
