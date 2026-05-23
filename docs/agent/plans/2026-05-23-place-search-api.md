# EXEC_PLAN — place-search-api

| 항목 | 값 |
|---|---|
| Task | place-search-api |
| Type | feature |
| Branch | feature/place-search-api |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/place-search-api |
| Port | 9000 |
| 생성 시각 | 2026-05-23 12:27 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

KickLog 백엔드에 카카오 Local REST API 기반 장소 검색 프록시를 추가한다. iOS는 카카오 REST 키를 알지 않고, 백엔드는 카카오 응답을 KickLog의 안정적인 `PlaceSearchResponse` DTO로 변환한다.

## 2. 접근 (Approach)

- API
  - `GET /places/search?q={keyword}&lat={lat?}&lng={lng?}&radius={radius?}` 인증 필요
  - 응답: `PlaceSearchResponse(places: List<Place>)`
  - `Place`: `provider`, `providerPlaceId`, `name`, `address`, `roadAddress`, `lat`, `lng`, `distanceM`
- 구현 패키지
  - `place/controller/PlaceController.kt`
  - `place/service/PlaceService.kt`
  - `place/service/KakaoLocalClient.kt`
  - `place/dto/PlaceDtos.kt`
- 설정
  - `kicklog.kakao.rest-api-key`
  - `kicklog.kakao.local-search-url`
- 규칙
  - DB 스키마 변경 없음
  - 카카오 REST API 키는 서버 환경변수로만 관리한다.
  - 카카오 응답 필드(`place_name`, `road_address_name`, `x`, `y`)는 외부로 노출하지 않는다.
  - `radius`는 기본 5000m, 최대 20000m로 제한한다.
  - `lat/lng`는 둘 다 있을 때만 카카오 `x/y/radius` 파라미터로 전달한다.
  - 카카오 5xx/timeout/호출 실패는 `EXTERNAL_KAKAO_UNAVAILABLE` 502로 변환한다.

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### (3-A) 인수 시나리오 (Gherkin)
@place @smoke
Feature: 장소 검색
  Scenario: 로그인 사용자가 키워드로 장소를 검색한다
    Given 로그인한 사용자가 있다
    And 카카오 Local API가 "풍경운동장" 검색 결과를 반환한다
    When /places/search?q=풍경운동장&lat=37.5&lng=127.0 로 요청한다
    Then 200 응답과 KickLog Place DTO 목록이 반환된다

  Scenario: 인증 없이 장소 검색을 요청하면 거부된다
    When /places/search?q=풍경운동장 로 요청한다
    Then 401 응답이 반환된다

### (3-B) 유스케이스 / 단위 테스트 케이스
- `PlaceService.search`는 blank query를 `VALIDATION_FAILED`로 거부한다.
- `PlaceService.search`는 radius 기본값 5000, 최대값 20000을 적용한다.
- `KakaoLocalClient.searchKeyword`는 카카오 documents를 KickLog Place DTO로 변환한다.
- `KakaoLocalClient.searchKeyword`는 카카오 장애를 `EXTERNAL_KAKAO_UNAVAILABLE`로 변환한다.

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew check`
- iOS: 자동 검증 없음 (사용자가 Xcode 에서 수동 빌드)

### 시나리오 검증 (수동)
- access token 없이 `/places/search?q=풍경운동장` 호출 시 401
- access token 포함 후 `/places/search?q=풍경운동장` 호출 시 카카오 검색 결과 DTO 반환

### 커버리지
- 장소 검색 service/client mapping과 실패 변환 테스트 추가

---

## (Optional) 위험도 / 롤백

Risk = Caution. 외부 카카오 API 의존과 신규 보호 endpoint가 추가된다. DB 변경은 없다.

## (Optional) 후속 / 관련 이슈

- 다음 PR: `venues` 저장/목록 API
- iOS 지도 SDK 도입 여부는 UI/UX 결정 이후 별도 작업

---

## TDD 작업 흐름

```
1. 위의 "3. 테스트 케이스" 섹션 채우기 (사용자가 결정)
2. 🔴 RED:
   - test-writer agent에게 위 케이스를 코드로 변환 위임
   - ./gradlew test (or Cmd+U) → 모두 실패 확인
3. 🟢 GREEN:
   - 한 케이스씩 최소 구현
   - 테스트 통과
4. 🔵 REFACTOR:
   - 중복 제거, 메서드 분리, 네이밍 정리
   - 테스트 여전히 통과
5. 다음 케이스 반복
6. 모든 케이스 통과 → "4. 검증" 섹션의 명령 실행
7. PR 생성 (/pr-guide)
```

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
