# ADR-0003: 백엔드 데이터 모델 + REST API 스키마

- **Status**: Accepted
- **Date**: 2026-05-21
- **방법**: `/grill-me` 인터뷰 (D1 ~ D10, 약 2시간)
- **선행 ADR**: ADR-0001 (MVP 스코프)

## Context

ADR-0001에서 백엔드 도입(Kotlin + Spring Boot + PostgreSQL)과 친구 기능을 채택한 후, 실제 데이터 모델·API 인터페이스·인증·동기화 정책이 미정 상태였다. 본 ADR이 코딩 시작 전 모든 데이터 경계를 정한다.

스코프 안:
- PostgreSQL 스키마 (테이블·인덱스·제약)
- 인증 흐름 (Sign in with Apple + Kakao Login)
- JWT 토큰 정책
- 사용자 삭제 정책 (Apple 심사)
- iOS ↔ Server 동기화 정책
- REST API 엔드포인트 목록

스코프 밖 (후속 ADR):
- SwiftData 모델 디테일 + HealthKit 매핑 → **ADR-0004**
- 초대 링크 Universal Link AASA 구조 → **ADR-0005**
- 백엔드 호스팅 선택 → **ADR-0006**
- 자동 그룹핑 시간/위치 임계값 → **ADR-0002**

---

## Decisions

### D1. 서버 영속화 단위 — **쿼터별 집계만**

- **선택**: (B) 쿼터별 집계 — 4 헤드라인 지표 + 쿼터 1~4 각각의 집계
- **고려한 옵션**:
  - (A) 집계 지표만 (헤드라인 4개)
  - (B) 쿼터별 집계 (선택)
  - (C) + 1분 단위 시계열
  - (D) + GPS 경로
  - (E) 모든 raw 시계열
- **이유**:
  - PRD 친구 기능 화면이 "쿼터별 막대그래프 3종" — (B)와 1:1 매칭
  - 1경기 ~2KB → 사용자당 한 시즌 50KB 미만, 운영비 무시 가능
  - iOS HealthKit raw는 iOS가 SoT로 유지
  - **Apple 심사**: HealthKit 데이터 server 저장은 "필요한 만큼만" 원칙. (E)는 거부 위험.
  - v1.1+ 시계열·GPS 경로 필요해지면 별도 테이블 추가
- **v1.1+ 후보**: 운동장 히트맵 그리드 (`heatmap_grid_json`) 추가 시 데이터 크기 +500B/쿼터

### D2. User 식별자 — **display_name만**

- **선택**: (A) display_name만 (한글/영문/이모지 자유, 1~50자, **자유 변경**)
- **고려한 옵션**: (A) display만, (B) Twitter식 username + display, (C) username만, (D) Apple name 그대로
- **이유**:
  - 본인+팀원 10~20명 규모에 username 시스템은 over-engineering
  - PRD가 친구 검색을 "보조"로 정의 — 부분 일치로 충분
  - Apple Sign-In의 name field 자동 매핑 (가입 마찰 0)
  - v1.1+ 사용자 풀 확장 시 `users.username` nullable 컬럼 추가로 마이그레이션 단순

### D3. Friendship 모델 — **정렬 pair 1 row + initiator**

- **선택**: (C) 정렬 pair + initiator — `(user_low_id, user_high_id) UNIQUE`
- **고려한 옵션**: (A) 2 row 대칭, (B) 단방향 1 row, (C) 정렬 pair (선택)
- **이유**:
  - 데이터 정규화 (1 row per 관계, 중복 없음)
  - 쌍방 동시 요청도 자연 처리 (`ON CONFLICT` UPSERT)
  - 친구 삭제 시 1 row DELETE (트랜잭션 불필요)
  - `LEAST/GREATEST` 강제로 같은 두 사용자 사이 항상 1 row 보장

### D4. FriendInvitation — **8자 base62 + N회용 + 15일 만료**

- **선택**: (B) Short Code 8자 base62 + 사용 횟수 무제한 + 15일 만료
- **고려한 옵션**: (A) UUID + 1회용 + 7일, (B) Short Code + N회용 + 15일 (선택), (C) 사용자 정의
- **이유**:
  - 단톡방 시나리오 = 한 링크로 여러 명 클릭 — (A) 1회용은 부적합
  - 8자 base62 = 218조 조합, 추측 안전
  - URL 짧음: `kicklog.org/i/xY9k2Lp4` (도메인 확정: ADR-0007)
  - 15일은 본인+팀원이 시즌 중 새 멤버 들어올 때 재사용 가능 + 너무 오래 안 살게

### D5. Match + QuarterWorkout — **Client UUID + HealthKit UUID 부속**

- **선택**: (B) Client-generated Match UUID (iOS가 생성) + 쿼터별 HealthKit UUID
- **고려한 옵션**: (A) HealthKit UUID 기반, (B) Client UUID 기반 (선택), (C) (user_id, played_at) 자연키, (D) Hybrid
- **이유**:
  - **라벨링 수정이 가장 흔한 시나리오** (골 수 정정, 상대팀 수정) — 같은 client_match_id로 PUT만 하면 끝
  - HealthKit 데이터 삭제 후 재생성 시 HK UUID 바뀜 — Client UUID는 SwiftData에 보존
  - 같은 운동장 같은 날 두 경기 가능
  - 쿼터 레벨에 HK UUID도 저장 → 동일 워크아웃이 다른 match에 잘못 매핑 방지

### D6. Venue 모델 — **개인 운동장 + 단순 lat/lng (PostGIS X)**

- **선택**: (A) 개인 운동장 + `NUMERIC(9,6)` lat/lng, iOS가 Haversine 매칭 (반경 100m)
- **고려한 옵션**: (A) 개인 + 단순 (선택), (B) 개인 + PostGIS, (C) 공유 운동장
- **이유**:
  - 본인 venue N=2~5개 환경에서 PostGIS over-engineering
  - 100m 반경 매칭에 GPS 노이즈 ±5m 무시 가능
  - Railway/Fly.io 기본 PostgreSQL에 PostGIS 없음 (별도 이미지 필요) — 의존성 줄임
  - v1.1+ 공유 운동장 도입 시 `ALTER TABLE ADD COLUMN geom geometry(Point, 4326)` 단순 마이그레이션

### D6.1. 운동장 등록 UX — **Hybrid (자동 GPS + 카카오 검색 옵션) + 백엔드 프록시**

- **선택**: (v) Hybrid — 자동 GPS 채움 기본 + "정확한 위치 검색" 옵션
- **검색 API**: 카카오 로컬 키워드 검색 (한국 POI 정확도 1위)
- **호출 방식**: **백엔드 프록시** (`/places/search` 엔드포인트)
- **이유**:
  - 90% 케이스 = 자동 GPS로 충분 (마찰 0)
  - 한국 운동장 POI는 카카오가 Apple MapKit 대비 정확
  - **백엔드 프록시 필수**: REST API 키 클라이언트 노출 방지, rate limit, 캐싱, 통계
  - 본인이 백엔드 개발자 → 풀스택 학습 가치 (Spring `WebClient` + `@Cacheable`)
  - v1.1: Redis 캐시 + 카카오 호출 통계 → 공유 운동장 후보 자동 추출

### D7. OAuth Providers — **Apple + Kakao 별도 계정**

- **선택**: Apple Sign-In + Kakao Login 모두 지원, 별도 계정 정책
- **Apple 심사 4.8**: OAuth 제공 시 Sign in with Apple도 **반드시** 동등 제공 → 둘 다 유지 필수
- **다중 provider 처리**: (A) MVP는 별도 계정 — 한 사람이 둘 다 쓰면 별도 계정으로 인식, v1.1에서 "계정 연결" 기능
- **고려한 옵션**: (A) 별도 계정 (선택), (B) Email 기반 자동 통합, (C) 첫 가입 후 추가 연결
- **이유**:
  - Apple proxy email 사용 시 (B) Email 통합 불가능
  - MVP 단순성: oauth_identities 테이블에 1 row per identity
  - v1.1 확장 시 같은 user_id에 multiple identity 허용 (스키마 변경 없음)

### D7.1. JWT 토큰 정책 — **Access (15m) + Refresh (30d) + Rotation**

- **선택**: (B) Access (15m) + Refresh (30d), DB 저장 + refresh rotation + 사용자별 강제 로그아웃 가능
- **고려한 옵션**: (A) Access only (90d long-lived), (B) Access + Refresh, (C) Apple/Kakao token 직접 사용, (D) Refresh rotation 포함
- **이유**:
  - OAuth 2.0 표준 (본인 백엔드 개발자 학습 가치)
  - 사용자 마찰 0 (자동 refresh)
  - 보안 사고 시 refresh token revoke로 강제 로그아웃 가능
  - 위치·운동 기록을 다루므로 refresh 탈취 피해를 줄이기 위해 rotation 적용
  - Apple/Kakao identity token은 만료 10분 — 매번 검증 부적합 (C)
- **v1.1+**: 디바이스별 세션 관리 화면, refresh 재사용 알림

### D8. 사용자 삭제 — **Soft delete + 30일 grace + hard delete**

- **선택**: (B) Soft → 30일 grace → cron으로 hard delete
- **고려한 옵션**: (A) 즉시 hard, (B) Soft + grace (선택), (C) 영구 익명화, (D) 즉시 익명화 + 30일 hard
- **이유**:
  - **Apple 심사 5.1.1(v)** 표준 패턴
  - 사용자 실수 보호 (30일 내 복구)
  - 개인정보보호법 (GDPR/KISA): 30일 grace는 일반적 허용 범위
  - 친구 관점: `deleted_at IS NULL` 필터로 즉시 친구 목록에서 사라짐
  - cron job 1개 (`@Scheduled` 매일 새벽 4시)

### D9. 동기화 정책 — **단순 fire-and-forget + 재시도**

- **선택**: (A) iOS 라벨링 완료 시 PUT 1번, 실패 시 `synced_at = nil`, 앱 진입 시 재시도
- **고려한 옵션**: (A) 단순 + 재시도 (선택), (B) 큐 + exponential backoff, (C) 백그라운드 sync
- **이유**:
  - **iOS가 1차 SoT** (HealthKit raw + SwiftData 메타데이터), 서버는 백업 + 친구 공유 채널
  - 본인+팀원 환경에서 인터넷 거의 항상 있음
  - PUT 멱등 (D5)으로 재시도 안전성 보장
  - 사용자 인지 명확: "동기화 대기 N건" 배너 + "다시 시도" 버튼
  - v1.1+ 필요해지면 (B)/(C) 도입

### D9.1. SoT 범위 — **매 경기 데이터에 한정 (집계 derive는 백엔드)**

- **본인/친구 매 경기 데이터** (`Match`, `QuarterWorkout`) = **iOS SwiftData가 1차 SoT** (D9), 백엔드 매 경기 저장은 백업 + 친구 공유 채널
- **본인/친구 시즌·월별 집계** = **백엔드 SQL derive** (`SeasonStatService`, `GET /users/:userId/seasons/:year`)
- **이유**:
  - 집계 알고리즘 단일 소스 — 본인/친구 코드 1벌, 언어 간(Swift/Kotlin) divergence 위험 0
  - 시즌은 가끔 보는 화면 — 매 경기 카드의 즉각성과 달리 PUT 완료 후 정합으로 UX 충분
  - 백엔드 `SeasonStatService.calculate()`가 본인/친구 동일 (PR #11)
- **iOS 클라이언트 행태**:
  - 매 경기 카드 → SwiftData `FetchDescriptor` (즉시 + 오프라인 OK)
  - 본인 시즌 통계 → 백엔드 API 호출 (오프라인 시 표시 불가)
- **트레이드오프**: PUT 미완료 경기는 시즌 합계에 누락 — D9의 "동기화 대기 N건" 배너로 사용자 인지 채널 제공
- **v1.1+**: 오프라인 가치 vs 코드 2벌 부담 재평가 시 iOS reduce로 이전 가능 (ADR-0004 D9 참조)

### D10. REST API 엔드포인트 목록

전체 목록은 본 ADR 끝 [API Endpoints](#api-endpoints) 섹션 참조. 별도 결정 사항 없음 — D1~D9에서 자연 도출.

---

## PostgreSQL Schema (V2 마이그레이션 후보)

> V1은 placeholder. 본 ADR 채택 후 V2부터 실제 스키마.

```sql
-- =========================================
-- V2__core_schema.sql
-- =========================================

-- Users (display_name 기반)
-- NOTE: hide_heart_rate 컬럼은 V11 마이그레이션으로 폐기됨 (PRD 단순화 — 친구는 모든 지표 평문 조회).
CREATE TABLE users (
  id              BIGSERIAL PRIMARY KEY,
  display_name    VARCHAR(50)  NOT NULL,
  email           VARCHAR(255),                       -- 첫 가입 provider에서 받은 것
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ                         -- soft delete (30일 grace)
);
CREATE INDEX idx_users_display_name ON users(display_name) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_deleted_at   ON users(deleted_at) WHERE deleted_at IS NOT NULL;

-- OAuth Identities (Apple + Kakao, 1 user에 1 provider per MVP)
CREATE TABLE oauth_identities (
  id                BIGSERIAL PRIMARY KEY,
  user_id           BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider          VARCHAR(20)  NOT NULL,            -- 'apple' | 'kakao'
  provider_user_id  VARCHAR(255) NOT NULL,            -- Apple sub or Kakao id
  email             VARCHAR(255),
  linked_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (provider, provider_user_id),
  CHECK (provider IN ('apple', 'kakao'))
);
CREATE INDEX idx_oauth_user ON oauth_identities(user_id);

-- Refresh Tokens
CREATE TABLE refresh_tokens (
  jti           UUID         PRIMARY KEY,
  user_id       BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at    TIMESTAMPTZ  NOT NULL,
  revoked_at    TIMESTAMPTZ,
  device_info   VARCHAR(255),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  last_used_at  TIMESTAMPTZ
);
CREATE INDEX idx_refresh_user ON refresh_tokens(user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_refresh_expires ON refresh_tokens(expires_at) WHERE revoked_at IS NULL;

-- Friendships (정렬 pair + initiator)
CREATE TABLE friendships (
  id                BIGSERIAL PRIMARY KEY,
  user_low_id       BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_high_id      BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status            VARCHAR(20)  NOT NULL,            -- 'pending' | 'accepted'
  initiated_by_id   BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  accepted_at       TIMESTAMPTZ,
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (user_low_id, user_high_id),
  CHECK (user_low_id < user_high_id),
  CHECK (status IN ('pending', 'accepted'))
);
CREATE INDEX idx_friend_low  ON friendships(user_low_id, status);
CREATE INDEX idx_friend_high ON friendships(user_high_id, status);

-- Friend Invitations 테이블은 V13 (P1) 에서 폐기됨 — friend_invitations DROP TABLE.
-- V12 의 users.display_name UNIQUE 도입으로 닉네임 검색만으로 친구 식별 가능 → 초대 링크 불필요.

-- Venues (개인 운동장)
CREATE TABLE venues (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        VARCHAR(100) NOT NULL,
  geo_lat     NUMERIC(9,6) NOT NULL,
  geo_lng     NUMERIC(9,6) NOT NULL,
  address     VARCHAR(255),
  road_address VARCHAR(255),
  provider    VARCHAR(20),
  provider_place_id VARCHAR(255),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, name)
);
CREATE INDEX idx_venues_user ON venues(user_id);

-- Matches (경기 단위)
CREATE TABLE matches (
  id                BIGSERIAL PRIMARY KEY,
  user_id           BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_match_id   UUID         NOT NULL,
  played_at         TIMESTAMPTZ  NOT NULL,
  venue_id          BIGINT                REFERENCES venues(id) ON DELETE SET NULL,
  opponent_name     VARCHAR(100),
  result            VARCHAR(1),                       -- 'W' | 'D' | 'L' | NULL — team_goals vs opponent_goals 로 백엔드 자동 derive (V10+)
  position          VARCHAR(2),                       -- 'GK' | 'DF' | 'MF' | 'FW' | NULL
  user_goals        SMALLINT,                         -- 본인이 직접 넣은 골
  team_goals        INTEGER,                          -- 팀 전체 골 (V10+). NULL=미입력
  opponent_goals    INTEGER,                          -- 상대팀 골 (V9+). NULL=미입력
  user_assists      SMALLINT,
  -- 헤드라인 4지표
  total_distance_m  INT          NOT NULL,
  max_speed_kmh     NUMERIC(4,1) NOT NULL,
  sprint_count      SMALLINT     NOT NULL,
  avg_heart_rate    SMALLINT     NOT NULL,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, client_match_id),
  CHECK (result IN ('W','D','L') OR result IS NULL),
  CHECK (position IN ('GK','DF','MF','FW') OR position IS NULL),
  CHECK (user_goals IS NULL OR user_goals >= 0),
  CHECK (user_assists IS NULL OR user_assists >= 0),
  CHECK (team_goals IS NULL OR team_goals >= 0),
  CHECK (team_goals IS NULL OR team_goals >= user_goals)  -- 본인 골은 팀 골 초과 불가 (V10+)
);

-- 매치 결과(result) 도출 규칙 (V10+):
--   result = derive(team_goals, opponent_goals)
--     · 둘 중 하나라도 NULL  → result = NULL ("점수 모름" 상태)
--     · team_goals >  opponent_goals → 'W'
--     · team_goals == opponent_goals → 'D'
--     · team_goals <  opponent_goals → 'L'
-- 클라이언트는 result 필드를 보낼 수 없다 (UpsertMatchRequest 에서 제거됨). 보내도 무시.
-- 기존 row 의 result 가 'W'/'D'/'L' 이지만 team_goals 가 NULL 인 경우, 사용자가 라벨링을 다시 저장하면 (team_goals 미입력 유지 시) result 는 NULL 로 의도적 리셋된다.
-- user_goals 는 NOT NULL DEFAULT 0 (미입력 = 0 으로 간주), team_goals / opponent_goals 는 NULL 허용 (모름 상태).
CREATE INDEX idx_matches_user_played ON matches(user_id, played_at DESC);

-- Quarter Workouts (쿼터별 집계)
CREATE TABLE quarter_workouts (
  id                    BIGSERIAL PRIMARY KEY,
  match_id              BIGINT       NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  quarter_no            SMALLINT     NOT NULL,
  source_workout_uuid   VARCHAR(36)  NOT NULL,        -- HealthKit HKWorkout UUID
  started_at            TIMESTAMPTZ  NOT NULL,
  ended_at              TIMESTAMPTZ  NOT NULL,
  duration_seconds      INT          NOT NULL,
  -- 쿼터별 집계
  distance_m            INT          NOT NULL,
  avg_speed_kmh         NUMERIC(4,1) NOT NULL,
  avg_heart_rate        SMALLINT     NOT NULL,
  max_heart_rate        SMALLINT     NOT NULL,
  sprint_count          SMALLINT     NOT NULL,
  active_energy_kcal    SMALLINT     NOT NULL,
  trimmed               BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (match_id, quarter_no),
  UNIQUE (match_id, source_workout_uuid),
  CHECK (quarter_no BETWEEN 1 AND 4)
);
CREATE INDEX idx_quarter_match ON quarter_workouts(match_id, quarter_no);
```

---

## API Endpoints

### Auth
```
POST   /auth/apple/signin           { identityToken, name? }
POST   /auth/kakao/signin           { kakaoAccessToken }
POST   /auth/refresh                { refreshToken }
POST   /auth/logout                 (Authorization)
POST   /auth/logout/this-device     { refreshToken }
```

### Users
```
GET    /users/me                    내 프로필
PATCH  /users/me                    display_name 수정 (단일 필드)
DELETE /users/me                    계정 삭제 (soft, 30일 grace)
POST   /users/me/cancel-deletion    삭제 취소
GET    /users/search?q=...&limit=20 친구 검색 (display_name 부분 일치)
```

### Friends
```
GET    /friendships                 내 친구 목록 (status=accepted)
GET    /friendships/pending         받은 친구 요청 목록
POST   /friendships                 친구 요청 (targetUserId 단독 — P1 에서 token 경로 폐기)
PATCH  /friendships/:id             수락
DELETE /friendships/:id             친구 끊기 / 거절
```

### Users 추가 endpoint (P1)
```
GET    /users/check-display-name?displayName=... 닉네임 가용 확인 (V12 UNIQUE INDEX)
```

### Invitations (폐기 — P1 V13)
초대 링크 도메인은 V13 에서 폐기됨. V12 의 닉네임 unique 도입으로 검색만으로 친구 식별 가능.

### Matches
```
PUT    /matches/:client_match_id    경기 업로드/수정 (멱등)
GET    /matches                     내 경기 리스트 (페이지네이션, 시즌 필터)
GET    /matches/:id                 경기 상세 (쿼터 포함)
DELETE /matches/:id                 경기 삭제
GET    /users/:userId/matches       친구의 경기 (read-only, 권한 검증)
GET    /users/:userId/matches/:id   친구 경기 상세
```

### Venues
```
GET    /venues                      내 운동장 목록
POST   /venues                      등록 { name, geo_lat, geo_lng, provider?, provider_place_id? }
GET    /venues/:id                  상세
PATCH  /venues/:id                  이름 수정
DELETE /venues/:id                  삭제 (관련 match.venue_id → NULL)
```

### Places (카카오 프록시)
```
GET    /places/search?q=...&lat=...&lng=...&radius=5000
                                    카카오 키워드 검색 프록시 (캐시 24h, v1.1)
```

### Statistics
```
GET    /users/me/seasons/:year      내 시즌 통계 (시즌 카드 6개)
GET    /users/:userId/seasons/:year 친구 시즌 통계 (권한 검증)
```

---

## 인증 흐름 상세

### Apple Sign-In
```
1. iOS: ASAuthorizationAppleIDProvider().createRequest()
2. 사용자 인증 → identityToken (JWT) + (첫 가입) name 받음
3. POST /auth/apple/signin { identityToken, name? }
4. 백엔드:
   a. Apple JWKS 공개키로 token 검증 (kid·alg·iss·aud·exp)
   b. token.sub → apple_user_id
   c. SELECT oauth_identities WHERE provider='apple' AND provider_user_id=sub
   d. 없으면 INSERT users + oauth_identities (display_name from name)
   e. JWT 발급
5. iOS ← { accessToken (15m), refreshToken (30d), user }
```

### Kakao Login
```
1. iOS: KakaoOpenSDK loginWithKakaoTalk
2. accessToken 획득
3. POST /auth/kakao/signin { kakaoAccessToken }
4. 백엔드:
   a. GET https://kapi.kakao.com/v2/user/me with Authorization
   b. { id, kakao_account.email, kakao_account.profile.nickname }
   c. SELECT oauth_identities WHERE provider='kakao' AND provider_user_id=id
   d. 없으면 INSERT users + oauth_identities (display_name from nickname)
   e. JWT 발급
5. iOS ← { accessToken, refreshToken, user }
```

### Token Refresh
```
POST /auth/refresh { refreshToken }
→ 백엔드: jti 추출 → refresh_tokens DB 확인 → revoked_at IS NULL && expires_at > NOW()
→ 새 accessToken 발급 + last_used_at 갱신
```

---

## 사용자 삭제 흐름 (cron 포함)

```kotlin
@Scheduled(cron = "0 0 4 * * *")  // 매일 새벽 4시
fun purgeDeletedUsers() {
    val cutoff = Instant.now().minus(30, ChronoUnit.DAYS)
    val toDelete = userRepository.findByDeletedAtBefore(cutoff)
    toDelete.forEach { user ->
        userRepository.hardDelete(user.id)  // CASCADE로 모든 데이터 삭제
        log.info("Hard deleted user {} (deleted_at {})", user.id, user.deletedAt)
    }
}
```

친구 관점에서 즉시 사라짐:
```sql
-- 모든 친구 관련 쿼리에 deleted_at IS NULL 필터
SELECT u.* FROM friendships f
JOIN users u ON (u.id = f.user_low_id OR u.id = f.user_high_id) AND u.id != $X
WHERE (f.user_low_id = $X OR f.user_high_id = $X)
  AND f.status = 'accepted'
  AND u.deleted_at IS NULL;
```

---

## 동기화 정책 상세

iOS SwiftData 모델에 동기화 상태 필드:
```swift
@Model
final class Match {
    @Attribute(.unique) var clientMatchId: UUID
    // ... 모든 데이터 필드
    var syncedAt: Date?              // nil = 미동기화
    var lastSyncAttemptAt: Date?
    var syncErrorMessage: String?
}
```

흐름:
1. 사용자 라벨링 완료 → `PUT /matches/:clientMatchId`
2. 성공: `syncedAt = Date()`
3. 실패: `syncedAt = nil` 유지, 에러 메시지 저장
4. 앱 진입 시 또는 사용자 "다시 시도" → 미동기화 항목 일괄 재업로드

iOS UI: "동기화 대기 N건" 배너 (미동기화 있을 때만 표시)

---

## Consequences

### 긍정
- **MVP 단순성** — 헥사고날·DDD 없이 단순 Spring 레이어로 충분
- **친구 기능 완전 매핑** — 데이터 모델이 PRD UI 1:1
- **Apple/Kakao 동등 지원** — 한국 사용자 친화 + Apple 심사 통과
- **멱등 PUT (D5)** — 재시도 안전
- **iOS SoT** — 멀티 디바이스 복잡도 회피, 서버 부담 최소
- **30일 grace** — 사용자 실수 보호 + 개인정보보호법 호환

### 부정 / 트레이드오프
- **테이블 9개** (users, oauth_identities, refresh_tokens, friendships, friend_invitations, venues, matches, quarter_workouts) — 1인 사이드치고는 많음
- **카카오 의존성** — REST API 키 관리 + 외부 API 장애 대응 필요
- **PostGIS 없음** — v1.1 공유 운동장 시 마이그레이션 비용
- **GPS 경로/히트맵 v1.1 후보** — 매력적 기능 보류
- **멀티 디바이스 미지원** — iPad 사용 시 v1.1 추가 작업

### 후속 결정 필요 (다른 ADR로)
- **ADR-0002**: 자동 그룹핑 시간/위치 임계값 (시간 60분/90분? 위치 100m/200m?)
- **ADR-0004**: SwiftData 모델 + HealthKit 매핑 (Item.swift 교체, iCloud Sync 도입 여부)
- **ADR-0005**: 초대 링크 Universal Link AASA 구조 (도메인 등록 필요?)
- **ADR-0006**: 백엔드 호스팅 선택 (Railway vs Fly.io + 카카오 outbound 응답 시간 고려)

---

## Revisions

| 날짜 | 변경 | 사유 |
|---|---|---|
| 2026-05-21 | 초기 작성 | grill-me 인터뷰 D1~D10 기반 |
| 2026-05-24 | D9.1 신설 — SoT 범위 명시 (매 경기 SwiftData / 시즌 집계 백엔드 derive) | grill-me 후속 결정 (ADR-0004 D9 cross-reference) |
