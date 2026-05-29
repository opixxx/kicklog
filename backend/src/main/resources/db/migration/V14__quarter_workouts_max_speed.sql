-- ADR-0001 D8 (2026-05-29 개정) — 쿼터별 최고속도 (max_speed_kmh) 컬럼 추가.
-- iOS 가 distance 샘플 기반 max 계산 + 35km/h sanity cap 적용한 값을 PUT 으로 전송.
-- 매치 detail 의 쿼터별 상세 카드에서 표시 (ADR-0001 D9 개정).
ALTER TABLE quarter_workouts
    ADD COLUMN max_speed_kmh DOUBLE PRECISION NOT NULL DEFAULT 0;
