-- iOS 와이어프레임의 "4-2 승" 같은 스코어 표시를 위해 상대팀 득점 컬럼 추가.
-- nullable — 미입력 매치 (스코어 모름) 와 "0:0 무승부" (Int 0) 를 구분.
ALTER TABLE matches
    ADD COLUMN opponent_goals INTEGER;
