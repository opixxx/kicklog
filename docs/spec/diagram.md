# KickLog 다이어그램

> Mermaid 로 작성 — GitHub·VS Code 에서 렌더링된다.
> 현재 수록: **ERD**(테이블 관계) + **인증 시퀀스**(Apple/Kakao/Refresh).
> 패키지·레이어 구조는 `architecture/overview.md`, 동기화 흐름은 ADR-0003 D9 의 ASCII 다이어그램 참조 (필요 시 본 문서로 이관).
>
> **정본 관계**: 스키마 정본은 ADR-0003 의 PostgreSQL Schema + Flyway 마이그레이션(`db/migration/V*.sql`). 인증 흐름 정본은 `architecture/auth.md`. 본 문서는 **시각화**이며, 충돌 시 정본 우선.

---

## 1. ERD — 데이터 모델

ADR-0003 의 8개 테이블. `users` 가 모든 도메인의 루트, 친구 관계는 `users` 자기참조(정렬 pair).

```mermaid
erDiagram
    users ||--o{ oauth_identities   : "has"
    users ||--o{ refresh_tokens      : "has"
    users ||--o{ friend_invitations  : "creates"
    users ||--o{ venues              : "owns"
    users ||--o{ matches             : "records"
    users ||--o{ friendships         : "user_low"
    users ||--o{ friendships         : "user_high"
    matches ||--|{ quarter_workouts  : "contains (1-4)"
    venues |o--o{ matches            : "played at (nullable)"

    users {
        bigserial   id PK
        varchar50   display_name
        varchar255  email "nullable"
        boolean     hide_heart_rate "def false"
        timestamptz created_at
        timestamptz updated_at
        timestamptz deleted_at "nullable, soft delete 30d grace"
    }

    oauth_identities {
        bigserial   id PK
        bigint      user_id FK
        varchar20   provider "apple | kakao"
        varchar255  provider_user_id
        varchar255  email "nullable"
        timestamptz linked_at
    }

    refresh_tokens {
        uuid        jti PK
        bigint      user_id FK
        timestamptz expires_at "30d"
        timestamptz revoked_at "nullable"
        uuid        rotated_to_jti "nullable"
        varchar255  device_info "nullable"
        timestamptz created_at
        timestamptz last_used_at "nullable"
    }

    friendships {
        bigserial   id PK
        bigint      user_low_id FK "low < high"
        bigint      user_high_id FK
        varchar20   status "pending | accepted"
        bigint      initiated_by_id FK
        timestamptz created_at
        timestamptz accepted_at "nullable"
        timestamptz updated_at
    }

    friend_invitations {
        bigserial   id PK
        bigint      inviter_id FK
        varchar8    token UK "base62"
        timestamptz expires_at "15d"
        int         use_count "def 0"
        timestamptz revoked_at "nullable"
        timestamptz created_at
    }

    venues {
        bigserial   id PK
        bigint      user_id FK
        varchar100  name "UK(user_id, name)"
        numeric     geo_lat "NUMERIC(9,6)"
        numeric     geo_lng "NUMERIC(9,6)"
        timestamptz created_at
    }

    matches {
        bigserial   id PK
        bigint      user_id FK
        uuid        client_match_id "UK(user_id, client_match_id)"
        timestamptz played_at
        bigint      venue_id FK "nullable, SET NULL"
        varchar100  opponent_name "nullable"
        varchar1    result "W|D|L|null"
        varchar2    position "GK|DF|MF|FW|null"
        smallint    user_goals "nullable"
        smallint    user_assists "nullable"
        int         total_distance_m
        numeric     max_speed_kmh "NUMERIC(4,1)"
        smallint    sprint_count
        smallint    avg_heart_rate
        timestamptz created_at
        timestamptz updated_at
    }

    quarter_workouts {
        bigserial   id PK
        bigint      match_id FK
        smallint    quarter_no "1-4, UK(match_id, quarter_no)"
        varchar36   source_workout_uuid "HK UUID, UK(match_id, uuid)"
        timestamptz started_at
        timestamptz ended_at
        int         duration_seconds
        int         distance_m
        numeric     avg_speed_kmh "NUMERIC(4,1)"
        smallint    avg_heart_rate
        smallint    max_heart_rate
        smallint    sprint_count
        smallint    active_energy_kcal
        boolean     trimmed "def false"
        timestamptz created_at
    }
```

### 관계 요약

| 부모 | 자식 | 카디널리티 | ON DELETE | 비고 |
|---|---|---|---|---|
| users | oauth_identities | 1:N | CASCADE | MVP 는 사실상 1:1 (provider 별 별도 계정, ADR-0003 D7) |
| users | refresh_tokens | 1:N | CASCADE | 기기/세션당 1 row |
| users | friendships | 1:N (×2) | CASCADE | `user_low_id`·`user_high_id` 양쪽 FK + `initiated_by_id` |
| users | friend_invitations | 1:N | CASCADE | inviter |
| users | venues | 1:N | CASCADE | `(user_id, name)` UNIQUE |
| users | matches | 1:N | CASCADE | `(user_id, client_match_id)` UNIQUE (멱등 PUT) |
| venues | matches | 0..1:N | **SET NULL** | venue 삭제해도 경기 보존 |
| matches | quarter_workouts | 1:N (1~4) | CASCADE | `quarter_no` 1~4, HK UUID 둘 다 UNIQUE |

> **friendships 자기참조 주의**: `user_low_id < user_high_id` CHECK 로 같은 두 사용자 사이 항상 1 row 보장 (ADR-0003 D3). 조회 시 `LEAST/GREATEST` 로 pair 정렬 후 접근.

---

## 2. 인증 시퀀스

정본은 `architecture/auth.md`. OAuth provider token 은 첫 가입·로그인 시 1회만, 이후 모든 API 는 우리 JWT.

### 2.1 Apple Sign-In

```mermaid
sequenceDiagram
    autonumber
    participant iOS
    participant API as KickLog Server
    participant Apple as Apple JWKS

    iOS->>iOS: ASAuthorizationAppleIDProvider<br/>→ identityToken (+ 첫 가입 시 name)
    iOS->>API: POST /auth/apple/signin<br/>{ identityToken, name? }
    API->>Apple: GET /auth/keys (공개키, 24h 캐시)
    Apple-->>API: JWKS 공개키
    API->>API: identityToken 검증<br/>(kid · alg=RS256 · iss · aud · exp)

    alt 검증 실패
        API-->>iOS: 401 AUTH_INVALID_APPLE_TOKEN
    else 검증 성공
        API->>API: SELECT oauth_identities<br/>WHERE provider='apple' AND provider_user_id=sub
        alt 기존 사용자
            API->>API: 기존 user_id 사용
        else 신규
            API->>API: INSERT users (display_name ← name)<br/>+ INSERT oauth_identities
        end
        API->>API: JWT 발급 (access 15m + refresh 30d)<br/>INSERT refresh_tokens
        API-->>iOS: 200 { accessToken, refreshToken, user }
    end
```

### 2.2 Kakao Login

```mermaid
sequenceDiagram
    autonumber
    participant iOS
    participant API as KickLog Server
    participant Kakao as Kakao API

    iOS->>iOS: KakaoOpenSDK loginWithKakaoTalk<br/>→ kakaoAccessToken
    iOS->>API: POST /auth/kakao/signin<br/>{ kakaoAccessToken }
    API->>Kakao: GET /v2/user/me<br/>Authorization: Bearer kakaoAccessToken
    alt 4xx (만료·invalid)
        Kakao-->>API: 401
        API-->>iOS: 401 AUTH_INVALID_KAKAO_TOKEN
    else 5xx / timeout
        API-->>iOS: 502 EXTERNAL_KAKAO_UNAVAILABLE
    else 정상
        Kakao-->>API: { id, kakao_account.profile.nickname, email }
        API->>API: provider_user_id = id<br/>(upsert — Apple 과 동일 분기)
        API->>API: JWT 발급 + INSERT refresh_tokens
        API-->>iOS: 200 { accessToken, refreshToken, user }
    end
```

### 2.3 Token Refresh

access token(15m) 만료 시 iOS 가 호출. refresh token 은 매 갱신마다 rotation 된다.

```mermaid
sequenceDiagram
    autonumber
    participant iOS
    participant API as KickLog Server
    participant DB as PostgreSQL

    iOS->>API: POST /auth/refresh<br/>{ refreshToken }
    API->>API: JwtTokenProvider.parse → jti 추출
    API->>DB: SELECT refresh_tokens WHERE jti=?
    alt 없음
        DB-->>API: -
        API-->>iOS: 401 AUTH_INVALID_REFRESH
    else revoked_at != null
        API->>DB: UPDATE refresh_tokens SET revoked_at=now WHERE user_id=? AND revoked_at IS NULL
        API-->>iOS: 401 AUTH_REFRESH_REUSED
    else expires_at <= now
        API-->>iOS: 401 AUTH_EXPIRED_REFRESH<br/>(→ iOS 재로그인 유도)
    else 유효
        API->>API: 새 accessToken + 새 refreshToken 발급
        API->>DB: UPDATE 기존 row SET revoked_at=now, rotated_to_jti=새 jti
        API->>DB: INSERT 새 refresh_tokens row
        API-->>iOS: 200 { accessToken, refreshToken }
    end
```

### 2.4 보호 endpoint 인증 (매 요청)

```mermaid
sequenceDiagram
    autonumber
    participant iOS
    participant Filter as JwtAuthenticationFilter
    participant Ctrl as Controller
    participant Svc as Service

    iOS->>Filter: 요청 + Authorization: Bearer accessToken
    alt 토큰 없음 / invalid / 만료
        Filter-->>iOS: 401 AUTH_INVALID_TOKEN / AUTH_EXPIRED_TOKEN<br/>(GlobalExceptionHandler 경유)
    else 유효
        Filter->>Filter: KickLogPrincipal(userId) → SecurityContext
        Filter->>Ctrl: @CurrentUser principal
        Ctrl->>Svc: Command(userId, ...)
        Note over Svc: 친구 데이터 경로면<br/>FriendshipAuthorizer.assertCanView 통과
        Svc-->>iOS: 200 Response
    end
```

---

## 변경 이력

| 날짜 | 변경 | 사유 |
|---|---|---|
| 2026-05-22 | 초기 작성 — ERD(8 테이블) + 인증 시퀀스 4종(Apple/Kakao/Refresh/보호 endpoint) Mermaid | 분산된 ASCII 다이어그램 통합 + ERD 신규. 구현 시 데이터 관계·인증 흐름 직참조용 |
