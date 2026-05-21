-- ============================================
-- KickLog initial schema (placeholder)
-- ============================================
-- 본 마이그레이션은 골격만. 실제 스키마는 ADR-0003 결정 후 작성.
-- ADR-0003: 백엔드 데이터 모델 / API 스키마

-- users: Sign in with Apple 기반 사용자
CREATE TABLE users (
    id              BIGSERIAL PRIMARY KEY,
    apple_user_id   VARCHAR(255) UNIQUE NOT NULL,
    username        VARCHAR(50)  UNIQUE NOT NULL,
    display_name    VARCHAR(100) NOT NULL,
    hide_heart_rate BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_username ON users(username);

-- 추후 ADR-0003에서 추가될 테이블:
-- - friendships (양방향 친구 관계)
-- - friend_invitations (초대 링크)
-- - matches (경기 메타데이터)
-- - quarter_workouts (쿼터별 워크아웃 매핑)
-- - venues (운동장 마스터)
-- - workout_metrics_summary (집계 지표 캐시)
