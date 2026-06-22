-- 중복 인덱스 제거 (P1-2).
-- V7 의 idx_matches_user_played_at (user_id, played_at) 는
-- V5 의 idx_matches_user_played_at_id (user_id, played_at, id) 의 접두사이므로 중복이다.
-- 커서 페이지네이션·시즌 범위 조회 모두 복합 인덱스로 커버되므로 단축 인덱스를 제거한다.
-- 주의: DROP INDEX 는 matches 에 짧은 ACCESS EXCLUSIVE 락을 잡는다 — 트래픽 적은 시간대 적용 권장.
DROP INDEX IF EXISTS idx_matches_user_played_at;
