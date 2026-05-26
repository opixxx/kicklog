-- 팀 전체 득점 컬럼 추가.
-- iOS 라벨링 화면에서 "본인 골" 과 분리되어 입력되며, result(W/D/L) 는 team_goals vs opponent_goals 로 자동 derive 한다.
-- nullable — 사용자가 점수를 모르는 경우 NULL 유지 (result 도 NULL).
ALTER TABLE matches
    ADD COLUMN team_goals SMALLINT;

-- 0 이상 검증 (Bean Validation 과 이중 안전망).
ALTER TABLE matches
    ADD CONSTRAINT matches_team_goals_min CHECK (team_goals IS NULL OR team_goals >= 0);

-- 본인이 넣은 골은 팀 전체 골을 초과할 수 없음 — 논리적 무결성.
ALTER TABLE matches
    ADD CONSTRAINT matches_team_goals_gte_user_goals CHECK (team_goals IS NULL OR team_goals >= goals);
