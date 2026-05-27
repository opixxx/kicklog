-- 친구에게 심박수 숨기기 토글 폐기 (PRD 단순화).
-- 친구는 본인의 모든 지표를 평문으로 본다 — 마스킹 정책 자체 제거.
-- 베타 단계 (사용자 ~2명) 라 데이터 보존 불필요. DROP COLUMN.
ALTER TABLE users DROP COLUMN hide_heart_rate;
