# KickLog API 명세

> **이 문서의 위치**: ADR-0003 이 endpoint **목록**(why)을, `architecture/api-conventions.md` 가 **규약**(URL·메서드·에러 포맷)을 정한다.
> 본 문서는 그 둘을 바탕으로 **endpoint 별 request/response body·상태 코드·에러·예시**(구현 시 직접 참조하는 계약)를 정형화한다.
> 충돌 시 우선순위: **ADR-0003 > api-conventions.md > 본 문서**. 본 문서가 어긋나면 갱신 PR 먼저.

- **Base URL**: 운영 `https://api.kicklog.app/v1` · 로컬 `http://localhost:8080/v1`
- **인증 헤더**: `Authorization: Bearer <accessToken>` (보호 endpoint 전부)
- **에러 응답**: 모든 에러는 `{ code, message, field?, traceId? }` (api-conventions.md)
- **시간**: 모든 `Instant` 는 ISO-8601 UTC (`2026-05-21T10:00:00Z`)
- **null**: 키를 빼지 않고 `null` 명시 (iOS 디코딩 일관성)
- **🔒 = 인증 필요 / 🌐 = permitAll**

---

## 목차

| # | 도메인 | endpoint 수 | 인증 |
|---|---|---|---|
| 1 | [Auth](#1-auth) | 5 | 🌐 (logout 계열만 🔒) |
| 2 | [Users](#2-users) | 5 | 🔒 |
| 3 | [Friends](#3-friends) | 5 | 🔒 |
| 4 | [Invitations](#4-invitations) | 4 | 🔒 (token 조회만 🌐) |
| 5 | [Matches](#5-matches) | 6 | 🔒 |
| 6 | [Venues](#6-venues) | 4 | 🔒 |
| 7 | [Places](#7-places) | 1 | 🔒 |
| 8 | [Statistics](#8-statistics) | 2 | 🔒 |

공통 에러 코드는 [부록 A](#부록-a-공통-errorcode)에, 공통 DTO 는 [부록 B](#부록-b-공통-dto)에.

---

## 1. Auth

OAuth provider token → 우리 JWT 교환. 세부 흐름은 `architecture/auth.md`, 시퀀스는 `diagram.md`.

### 1.1 `POST /auth/apple/signin` 🌐

Apple identityToken 으로 로그인/가입. 첫 가입 시 `name` 으로 `display_name` 초기화.

**Request**
```json
{
  "identityToken": "eyJraWQiOiJ...",
  "name": "김조축"
}
```
| 필드 | 타입 | 필수 | 비고 |
|---|---|---|---|
| `identityToken` | string | ✅ | Apple JWT (JWKS 검증 대상) |
| `name` | string | ❌ | 첫 가입 시에만 의미. 1~50자. 미제공 시 기본값 `"사용자"` |

**Response** `200` — [`SignInResponse`](#signinresponse)
```json
{
  "accessToken": "eyJ...",
  "refreshToken": "eyJ...",
  "user": { "id": 1, "displayName": "김조축", "email": "abc@privaterelay.appleid.com", "hideHeartRate": false }
}
```

**에러**

| status | code | 조건 |
|---|---|---|
| 401 | `AUTH_INVALID_APPLE_TOKEN` | identityToken 검증 실패 (kid·iss·aud·exp) |
| 502 | `EXTERNAL_APPLE_UNAVAILABLE` | Apple JWKS 조회 실패 |

> 신규 가입도 `200` 반환 (별도 `201` 안 씀 — 클라이언트가 가입/로그인 구분 불필요).

---

### 1.2 `POST /auth/kakao/signin` 🌐

Kakao accessToken 으로 로그인/가입. 백엔드가 `/v2/user/me` 호출해 검증.

**Request**
```json
{ "kakaoAccessToken": "AAAA..." }
```
| 필드 | 타입 | 필수 |
|---|---|---|
| `kakaoAccessToken` | string | ✅ |

**Response** `200` — [`SignInResponse`](#signinresponse) (Apple 과 동일 구조, `display_name` 은 kakao nickname)

**에러**

| status | code | 조건 |
|---|---|---|
| 401 | `AUTH_INVALID_KAKAO_TOKEN` | Kakao 토큰 4xx (만료·invalid) |
| 502 | `EXTERNAL_KAKAO_UNAVAILABLE` | Kakao 5xx / 타임아웃 |

---

### 1.3 `POST /auth/refresh` 🌐

Refresh token 으로 새 access token 과 새 refresh token 을 발급한다. 기존 refresh token 은 즉시 revoke 된다.

**Request**
```json
{ "refreshToken": "eyJ..." }
```

**Response** `200`
```json
{ "accessToken": "eyJ...", "refreshToken": "eyJ..." }
```
> refresh token rotation 적용. iOS 는 응답의 새 `refreshToken` 을 Keychain 에 덮어쓴다. user 객체는 미포함.

**에러**

| status | code | 조건 |
|---|---|---|
| 401 | `AUTH_INVALID_REFRESH` | DB 에 없음 |
| 401 | `AUTH_EXPIRED_REFRESH` | `expires_at <= now` |
| 401 | `AUTH_REFRESH_REUSED` | 이미 revoke 된 refresh token 재사용. 해당 사용자의 활성 세션 전체 revoke |

---

### 1.4 `POST /auth/logout` 🔒

사용자의 **모든** refresh token revoke (모든 기기 로그아웃).

**Request** 없음 · **Response** `204`

---

### 1.5 `POST /auth/logout/this-device` 🔒

해당 refresh token(JTI) 하나만 revoke.

**Request**
```json
{ "refreshToken": "eyJ..." }
```
**Response** `204`

> 본인 토큰이 아니면 `403 AUTH_REFRESH_NOT_OWNED`.

---

## 2. Users

내 프로필은 항상 `/users/me` (JWT 의 userId 사용, `/users/{myId}` 금지).

### 2.1 `GET /users/me` 🔒

**Response** `200` — [`UserResponse`](#userresponse)
```json
{ "id": 1, "displayName": "김조축", "email": "abc@example.com", "hideHeartRate": false, "createdAt": "2026-01-02T03:00:00Z" }
```
> 토큰·apple sub·kakao id 절대 미포함 (auth.md 보안 체크리스트).

---

### 2.2 `PATCH /users/me` 🔒

`display_name` / `hide_heart_rate` 부분 수정. 보낸 필드만 갱신.

**Request** (둘 다 optional, 최소 1개)
```json
{ "displayName": "김캡틴", "hideHeartRate": true }
```
| 필드 | 타입 | 검증 |
|---|---|---|
| `displayName` | string? | `@Size(min=1, max=50)` |
| `hideHeartRate` | boolean? | — |

**Response** `200` — [`UserResponse`](#userresponse)

**에러**: `400 VALIDATION_FAILED` (빈 문자열·50자 초과)

---

### 2.3 `DELETE /users/me` 🔒

Soft delete. `deleted_at = now` 설정 → 30일 후 cron 이 hard delete. 즉시 친구 목록에서 사라짐.

**Response** `204`
> 모든 refresh token 도 함께 revoke. 30일 내 [`POST /users/me/cancel-deletion`](#24-post-usersmecancel-deletion-) 으로 복구 가능.

---

### 2.4 `POST /users/me/cancel-deletion` 🔒

Soft delete 취소. `deleted_at = NULL`.

**Response** `200` — [`UserResponse`](#userresponse)

**에러**

| status | code | 조건 |
|---|---|---|
| 409 | `USER_NOT_DELETING` | 삭제 대기 상태가 아님 |
| 410 | `USER_PURGED` | 이미 30일 경과 hard delete 됨 |

> 이 endpoint 는 `deleted_at != NULL` 사용자도 접근해야 하므로 JWT 검증 시 deleted 상태를 통과시킨다 (다른 보호 endpoint 는 deleted 면 403/410).

---

### 2.5 `GET /users/search?q=...&limit=20` 🔒

`display_name` 부분 일치 검색 (친구 추가 보조). `deleted_at IS NULL` 만.

| 쿼리 | 타입 | 기본 | 비고 |
|---|---|---|---|
| `q` | string | — | 필수, 1자 이상 |
| `limit` | int | 20 | 최대 50 |

**Response** `200`
```json
{ "users": [ { "id": 7, "displayName": "박수비" } ] }
```
> 검색 결과에는 `email` 미포함 (최소 정보). 본인은 결과에서 제외.

---

## 3. Friends

정렬 pair 모델 (`user_low_id < user_high_id`, 1 row per 관계). 친구 추가는 token(초대링크) 또는 userId(검색).

### 3.1 `GET /friendships` 🔒

내 친구 목록 (`status = accepted`, 상대 `deleted_at IS NULL`).

**Response** `200`
```json
{
  "friends": [
    { "friendshipId": 12, "user": { "id": 7, "displayName": "박수비" }, "acceptedAt": "2026-03-01T00:00:00Z" }
  ]
}
```

---

### 3.2 `GET /friendships/pending` 🔒

**내가 받은** 친구 요청 (`status = pending` 且 `initiated_by_id != 나`).

**Response** `200`
```json
{
  "requests": [
    { "friendshipId": 15, "from": { "id": 9, "displayName": "이공격" }, "createdAt": "2026-05-20T12:00:00Z" }
  ]
}
```

---

### 3.3 `POST /friendships` 🔒

친구 요청 생성. `token`(초대 링크 경유) **또는** `targetUserId`(검색 경유) 중 정확히 하나.

**Request**
```json
{ "token": "xY9k2Lp4" }
```
또는
```json
{ "targetUserId": 7 }
```
| 필드 | 타입 | 비고 |
|---|---|---|
| `token` | string? | base62 8자. 초대 링크 |
| `targetUserId` | long? | 검색으로 찾은 사용자 |

> 둘 다 있거나 둘 다 없으면 `400 FRIEND_INVALID_REQUEST`.

**Response** `201`
```json
{ "friendshipId": 20, "status": "pending", "initiatedByMe": true }
```
> 상대가 이미 나에게 pending 요청을 보낸 상태였다면 `ON CONFLICT` 로 자동 수락되어 `status: "accepted"` 반환 가능.

**에러**

| status | code | 조건 |
|---|---|---|
| 409 | `FRIEND_ALREADY_EXISTS` | 이미 친구이거나 요청 대기 중 |
| 400 | `FRIEND_SELF_REQUEST` | 자기 자신에게 요청 |
| 404 | `USER_NOT_FOUND` | targetUserId 없음/탈퇴 |
| 410 | `INVITATION_EXPIRED` / `INVITATION_REVOKED` | token 무효 |

---

### 3.4 `PATCH /friendships/{id}` 🔒

받은 친구 요청 **수락**. `status: pending → accepted`, `accepted_at = now`.

**Request**
```json
{ "action": "accept" }
```
**Response** `200`
```json
{ "friendshipId": 15, "status": "accepted", "acceptedAt": "2026-05-22T09:00:00Z" }
```

**에러**

| status | code | 조건 |
|---|---|---|
| 403 | `FRIEND_NOT_RECIPIENT` | 내가 받은 요청이 아님 (내가 보낸 건 수락 불가) |
| 404 | `FRIEND_NOT_FOUND` | friendship 없음 |
| 409 | `FRIEND_ALREADY_ACCEPTED` | 이미 accepted |

---

### 3.5 `DELETE /friendships/{id}` 🔒

친구 끊기(accepted) 또는 요청 거절/취소(pending). 1 row DELETE.

**Response** `204`

**에러**: `403 FRIEND_NOT_PARTICIPANT` (당사자 아님), `404 FRIEND_NOT_FOUND`

---

## 4. Invitations

8자 base62 토큰, N회용, 15일 만료 (ADR-0003 D4). 링크 형태: `kicklog.app/i/{token}`.

### 4.1 `POST /invitations` 🔒

내 초대 링크 생성. 만료 15일 default.

**Request** 없음 (또는 `{}`)

**Response** `201`
```json
{
  "id": 3,
  "token": "xY9k2Lp4",
  "url": "https://kicklog.app/i/xY9k2Lp4",
  "expiresAt": "2026-06-06T09:00:00Z",
  "useCount": 0
}
```

---

### 4.2 `GET /invitations/{token}` 🌐

토큰 정보 조회 (수락 화면에서 발신자 미리보기). **인증 불필요** — 링크 클릭 시 비로그인 상태일 수 있음.

**Response** `200`
```json
{
  "token": "xY9k2Lp4",
  "inviter": { "id": 1, "displayName": "김조축" },
  "expiresAt": "2026-06-06T09:00:00Z",
  "valid": true
}
```

**에러**

| status | code | 조건 |
|---|---|---|
| 410 | `INVITATION_EXPIRED` | `expires_at <= now` |
| 410 | `INVITATION_REVOKED` | `revoked_at != null` |
| 404 | `INVITATION_NOT_FOUND` | 존재하지 않는 token |

---

### 4.3 `GET /invitations` 🔒

내가 만든 **활성** 링크 목록 (`revoked_at IS NULL AND expires_at > now`).

**Response** `200`
```json
{ "invitations": [ { "id": 3, "token": "xY9k2Lp4", "url": "...", "expiresAt": "...", "useCount": 2 } ] }
```

---

### 4.4 `DELETE /invitations/{id}` 🔒

링크 폐기. `revoked_at = now`.

**Response** `204` · **에러**: `403 INVITATION_NOT_OWNED`, `404 INVITATION_NOT_FOUND`

---

## 5. Matches

경기 단위. `client_match_id`(iOS UUID) 로 멱등 PUT (ADR-0003 D5). 쿼터 1~4개 부속.

### 5.1 `PUT /matches/{clientMatchId}` 🔒

경기 업로드/수정 (멱등 업서트). 같은 `clientMatchId` 재호출 시 전체 교체.

**Request** — [`PutMatchRequest`](#putmatchrequest)
```json
{
  "playedAt": "2026-05-18T01:00:00Z",
  "venueId": 5,
  "opponentName": "옆동네 FC",
  "result": "W",
  "position": "MF",
  "userGoals": 2,
  "userAssists": 1,
  "headline": {
    "totalDistanceM": 6800,
    "maxSpeedKmh": 27.3,
    "sprintCount": 14,
    "avgHeartRate": 158
  },
  "quarters": [
    {
      "quarterNo": 1,
      "sourceWorkoutUuid": "A1B2C3D4-...",
      "startedAt": "2026-05-18T01:00:00Z",
      "endedAt": "2026-05-18T01:25:00Z",
      "durationSeconds": 1500,
      "distanceM": 1800,
      "avgSpeedKmh": 7.2,
      "avgHeartRate": 152,
      "maxHeartRate": 178,
      "sprintCount": 4,
      "activeEnergyKcal": 240,
      "trimmed": false
    }
  ]
}
```
| 필드 | 타입 | 검증 |
|---|---|---|
| `playedAt` | Instant | `@NotNull` |
| `venueId` | long? | 본인 venue 만. 없으면 `404 VENUE_NOT_FOUND` |
| `opponentName` | string? | max 100 |
| `result` | string? | `@Pattern([WDL])` |
| `position` | string? | `GK\|DF\|MF\|FW` |
| `userGoals` / `userAssists` | int? | `@Min(0)` |
| `headline` | object | `@NotNull @Valid` — 4지표 전부 필수 |
| `quarters` | array | `@Size(min=1, max=4)`, `quarterNo` 1~4 유일 |

**Response** `200` (수정) / `201` (신규) — [`MatchDetailResponse`](#matchdetailresponse)

**에러**

| status | code | 조건 |
|---|---|---|
| 400 | `MATCH_QUARTER_OVERFLOW` | 쿼터 4개 초과 |
| 400 | `MATCH_DUPLICATE_QUARTER_NO` | quarterNo 중복 |
| 404 | `VENUE_NOT_FOUND` | venueId 가 내 것 아님 |

---

### 5.2 `GET /matches?page=0&size=20&season=2026` 🔒

내 경기 리스트. 페이지네이션 + 시즌(연도) 필터.

| 쿼리 | 기본 | 비고 |
|---|---|---|
| `page` / `size` | 0 / 20 | Pageable. size 최대 100 |
| `season` | (전체) | 연도. `played_at` 기준 |
| `sort` | `playedAt,desc` | — |

**Response** `200` — [`PageResponse`](#pageresponset)`<MatchSummaryResponse>`
```json
{
  "content": [
    { "id": 101, "playedAt": "2026-05-18T01:00:00Z", "venueName": "마포 풋살장", "opponentName": "옆동네 FC",
      "result": "W", "userGoals": 2, "userAssists": 1, "totalDistanceM": 6800, "quarterCount": 4 }
  ],
  "page": 0, "size": 20, "totalElements": 37, "totalPages": 2, "hasNext": true
}
```

---

### 5.3 `GET /matches/{id}` 🔒

내 경기 상세 (쿼터 전체 포함).

**Response** `200` — [`MatchDetailResponse`](#matchdetailresponse) · **에러**: `404 MATCH_NOT_FOUND`, `403 MATCH_NOT_OWNED`

---

### 5.4 `DELETE /matches/{id}` 🔒

경기 삭제 (CASCADE 로 quarter 도 삭제).

**Response** `204` · **에러**: `404 MATCH_NOT_FOUND`, `403 MATCH_NOT_OWNED`

---

### 5.5 `GET /users/{userId}/matches?page=0&size=20&season=2026` 🔒

**친구의** 경기 리스트 (read-only). `FriendshipAuthorizer.assertCanView` 통과 필수.

**Response** `200` — [`PageResponse`](#pageresponset)`<MatchSummaryResponse>`

**에러**

| status | code | 조건 |
|---|---|---|
| 403 | `FRIEND_UNAUTHORIZED` | accepted 친구 아님 (IDOR 방지) |
| 404 | `USER_NOT_FOUND` | 대상 없음/탈퇴 |

> `hideHeartRate=true` 인 친구의 데이터는 심박 필드를 `null` 로 마스킹.

---

### 5.6 `GET /users/{userId}/matches/{id}` 🔒

친구 경기 상세. 위와 동일 인가. **에러** 동일 + `404 MATCH_NOT_FOUND`.

> 응답은 [`MatchDetailResponse`](#matchdetailresponse) 이되, 친구의 `hideHeartRate` 면 `avgHeartRate`/`maxHeartRate` `null`.

---

## 6. Venues

개인 운동장. 단순 lat/lng (PostGIS X). iOS 가 Haversine 100m 매칭.

### 6.1 `GET /venues` 🔒

내 운동장 목록.

**Response** `200`
```json
{ "venues": [ { "id": 5, "name": "마포 풋살장", "geoLat": 37.556000, "geoLng": 126.923000 } ] }
```

---

### 6.2 `POST /venues` 🔒

운동장 등록.

**Request**
```json
{ "name": "마포 풋살장", "geoLat": 37.556000, "geoLng": 126.923000 }
```
| 필드 | 타입 | 검증 |
|---|---|---|
| `name` | string | `@NotBlank @Size(max=100)` |
| `geoLat` | BigDecimal | `@NotNull` `NUMERIC(9,6)` |
| `geoLng` | BigDecimal | `@NotNull` `NUMERIC(9,6)` |

**Response** `201`
```json
{ "id": 5, "name": "마포 풋살장", "geoLat": 37.556000, "geoLng": 126.923000 }
```
**에러**: `409 VENUE_NAME_DUPLICATE` (같은 사용자 내 이름 중복)

---

### 6.3 `PATCH /venues/{id}` 🔒

이름 수정 (좌표는 불변 — 새 위치면 새 venue).

**Request**
```json
{ "name": "마포 실내구장" }
```
**Response** `200` · **에러**: `403 VENUE_NOT_OWNED`, `404 VENUE_NOT_FOUND`, `409 VENUE_NAME_DUPLICATE`

---

### 6.4 `DELETE /venues/{id}` 🔒

삭제. 관련 `matches.venue_id → NULL` (ON DELETE SET NULL).

**Response** `204` · **에러**: `403 VENUE_NOT_OWNED`, `404 VENUE_NOT_FOUND`

---

## 7. Places

카카오 로컬 키워드 검색 프록시 (ADR-0003 D6.1). REST 키 클라이언트 노출 방지.

### 7.1 `GET /places/search?q=...&lat=...&lng=...&radius=5000` 🔒

| 쿼리 | 타입 | 기본 | 비고 |
|---|---|---|---|
| `q` | string | — | 필수. 검색 키워드 |
| `lat` / `lng` | BigDecimal | ❌ | 중심 좌표 (거리순 정렬용) |
| `radius` | int | 5000 | m. 최대 20000 (카카오 제한) |

**Response** `200`
```json
{
  "places": [
    {
      "provider": "kakao",
      "providerPlaceId": "123456789",
      "name": "마포 풋살장",
      "address": "서울 마포구 ...",
      "roadAddress": "서울 마포구 ...",
      "lat": 37.556,
      "lng": 126.923,
      "distanceM": 320
    }
  ]
}
```
> 카카오 응답 키(`place_name`, `road_address_name`, `x`, `y` 등)를 그대로 전달하지 않고 우리 DTO 로 변환 (api-conventions.md). `providerPlaceId` 는 카카오 장소 id이며, `distanceM` 은 `lat/lng` 미제공 시 `null`.

**에러**

| status | code | 조건 |
|---|---|---|
| 400 | `VALIDATION_FAILED` | `q` 누락 |
| 502 | `EXTERNAL_KAKAO_UNAVAILABLE` | 카카오 5xx/타임아웃 → iOS 는 자동 GPS fallback |

---

## 8. Statistics

시즌(연도) 집계 read-only. PRD 시즌 탭 카드 6종 매핑. **집계 계산은 백엔드** (iOS 는 본인 데이터 로컬 집계, 서버는 친구 통계 제공이 주 용도).

### 8.1 `GET /users/me/seasons/{year}` 🔒

내 시즌 통계.

**Response** `200` — [`SeasonStatResponse`](#seasonstatresponse)
```json
{
  "year": 2026,
  "totalDistanceM": 95400,
  "totalGoals": 18,
  "totalAssists": 11,
  "matchCount": 14,
  "quarterCount": 47,
  "best": {
    "maxSpeedKmh": 29.4,
    "longestMatchDistanceM": 8200,
    "mostSprintCount": 21
  }
}
```
> 데이터 없는 연도도 `200` + 0값 (404 아님 — 시즌 탭은 항상 카드 렌더).

---

### 8.2 `GET /users/{userId}/seasons/{year}` 🔒

친구 시즌 통계. `FriendshipAuthorizer` 통과 필수.

**Response** `200` — [`SeasonStatResponse`](#seasonstatresponse) (구조 동일)

**에러**: `403 FRIEND_UNAUTHORIZED`, `404 USER_NOT_FOUND`

---

## 부록 A. 공통 ErrorCode

> 정본은 `common/exception/ErrorCode.kt`. 본 표는 명세용 참조. 새 코드 추가 시 throw 지점도 함께 (code-reviewer Dead Code 규약).

| code | status | message (한글) |
|---|---|---|
| `VALIDATION_FAILED` | 400 | 입력값이 유효하지 않습니다 |
| `AUTH_INVALID_TOKEN` | 401 | 유효하지 않은 토큰입니다 |
| `AUTH_EXPIRED_TOKEN` | 401 | 토큰이 만료되었습니다 |
| `AUTH_INVALID_APPLE_TOKEN` | 401 | Apple 토큰 검증에 실패했습니다 |
| `AUTH_INVALID_KAKAO_TOKEN` | 401 | 카카오 토큰 검증에 실패했습니다 |
| `AUTH_INVALID_REFRESH` | 401 | 유효하지 않은 리프레시 토큰입니다 |
| `AUTH_EXPIRED_REFRESH` | 401 | 리프레시 토큰이 만료되었습니다 |
| `AUTH_REFRESH_REUSED` | 401 | 이미 사용된 리프레시 토큰입니다 |
| `AUTH_REFRESH_NOT_OWNED` | 403 | 본인의 토큰이 아닙니다 |
| `USER_NOT_FOUND` | 404 | 사용자를 찾을 수 없습니다 |
| `USER_DELETED` / `USER_PURGED` | 410 | 탈퇴한 사용자입니다 |
| `USER_NOT_DELETING` | 409 | 삭제 대기 상태가 아닙니다 |
| `FRIEND_INVALID_REQUEST` | 400 | token 또는 targetUserId 중 하나만 보내야 합니다 |
| `FRIEND_SELF_REQUEST` | 400 | 자기 자신에게 요청할 수 없습니다 |
| `FRIEND_UNAUTHORIZED` | 403 | 친구 관계가 아닙니다 |
| `FRIEND_NOT_RECIPIENT` | 403 | 받은 요청이 아닙니다 |
| `FRIEND_NOT_PARTICIPANT` | 403 | 해당 친구 관계의 당사자가 아닙니다 |
| `FRIEND_NOT_FOUND` | 404 | 친구 관계를 찾을 수 없습니다 |
| `FRIEND_ALREADY_EXISTS` | 409 | 이미 친구이거나 요청 대기 중입니다 |
| `FRIEND_ALREADY_ACCEPTED` | 409 | 이미 수락된 요청입니다 |
| `INVITATION_NOT_FOUND` | 404 | 초대 링크를 찾을 수 없습니다 |
| `INVITATION_NOT_OWNED` | 403 | 본인이 만든 링크가 아닙니다 |
| `INVITATION_EXPIRED` | 410 | 초대 링크가 만료되었습니다 |
| `INVITATION_REVOKED` | 410 | 폐기된 초대 링크입니다 |
| `MATCH_NOT_FOUND` | 404 | 경기를 찾을 수 없습니다 |
| `MATCH_NOT_OWNED` | 403 | 본인의 경기가 아닙니다 |
| `MATCH_QUARTER_OVERFLOW` | 400 | 쿼터는 4개를 초과할 수 없습니다 |
| `MATCH_DUPLICATE_QUARTER_NO` | 400 | 쿼터 번호가 중복되었습니다 |
| `VENUE_NOT_FOUND` | 404 | 운동장을 찾을 수 없습니다 |
| `VENUE_NOT_OWNED` | 403 | 본인의 운동장이 아닙니다 |
| `VENUE_NAME_DUPLICATE` | 409 | 같은 이름의 운동장이 이미 있습니다 |
| `EXTERNAL_APPLE_UNAVAILABLE` | 502 | Apple 서비스가 일시적으로 응답하지 않습니다 |
| `EXTERNAL_KAKAO_UNAVAILABLE` | 502 | 카카오 서비스가 일시적으로 응답하지 않습니다 |
| `INTERNAL_ERROR` | 500 | 서버 내부 오류가 발생했습니다 |

---

## 부록 B. 공통 DTO

> 명세용 형태. 실제 Kotlin `data class` 는 `coding-conventions` + `api-conventions.md` 의 DTO 흐름(Request→Command→Result→Response) 따름.

### SignInResponse
```json
{ "accessToken": "string", "refreshToken": "string", "user": "UserResponse(축약)" }
```
`user` 는 `{ id, displayName, email, hideHeartRate }` (createdAt 제외 축약형).

### UserResponse
```json
{ "id": 1, "displayName": "string", "email": "string|null", "hideHeartRate": false, "createdAt": "Instant" }
```

### PutMatchRequest
5.1 참조. `headline`(필수 4지표) + `quarters`(1~4) 중첩.

### MatchDetailResponse
```json
{
  "id": 101,
  "clientMatchId": "UUID",
  "playedAt": "Instant",
  "venue": { "id": 5, "name": "마포 풋살장" },
  "opponentName": "string|null",
  "result": "W|D|L|null",
  "position": "GK|DF|MF|FW|null",
  "userGoals": 2,
  "userAssists": 1,
  "headline": { "totalDistanceM": 6800, "maxSpeedKmh": 27.3, "sprintCount": 14, "avgHeartRate": 158 },
  "quarters": [ { "quarterNo": 1, "startedAt": "...", "endedAt": "...", "durationSeconds": 1500,
                  "distanceM": 1800, "avgSpeedKmh": 7.2, "avgHeartRate": 152, "maxHeartRate": 178,
                  "sprintCount": 4, "activeEnergyKcal": 240, "trimmed": false } ],
  "createdAt": "Instant",
  "updatedAt": "Instant"
}
```
> 친구 조회 시 `hideHeartRate=true` 면 `headline.avgHeartRate` 및 각 quarter 의 `avgHeartRate`/`maxHeartRate` 가 `null`.

### SeasonStatResponse
8.1 참조.

### PageResponse<T>
```json
{ "content": [], "page": 0, "size": 20, "totalElements": 0, "totalPages": 0, "hasNext": false }
```
`common/util/PageResponse.kt` 로 wrapping (Spring `Page` 기본 직렬화 미사용).

---

## 변경 이력

| 날짜 | 변경 | 사유 |
|---|---|---|
| 2026-05-22 | 초기 작성 — 9개 도메인 27 endpoint 전체 명세 + ErrorCode·공통 DTO 부록 | ADR-0003 endpoint 목록 + api-conventions.md 규약을 구현 직참조용 계약으로 정형화 |
