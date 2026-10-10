-- 시즌 통계 집계용 covering index (ADR-0014 후속 — 2026-09-20).
--
-- ADR-0014 로 집계를 DB 로 옮긴 뒤 부하 테스트에서 병목이 앱 → RDS 로 이동했다
-- (RDS CPU 66.8% → 80.9%). 그 다음 층을 여는 조치다.
--
-- 두 집계 쿼리 모두 인덱스로 행을 찾은 뒤 **힙에서 실제 값을 다시 읽고** 있었다.
-- INCLUDE 로 집계에 필요한 컬럼을 인덱스에 넣으면 Index Only Scan 이 되어 힙 접근이 사라진다.
--
-- 실측 (match 300k / quarter 1.2M, 사용자당 300경기):
--   ① 경기 집계   3.66ms  →  0.10ms   (−97%)
--   ② 쿼터 집계   9.86ms  →  1.24ms   (−87%, buffers 1,828 → 913)
--   합계         13.5ms  →  1.34ms   (−90%)   Heap Fetches: 0
--
-- ⚠️ Index Only Scan 은 **visibility map 에 의존**한다. VACUUM 이 돌지 않으면 힙을 다시 확인해
--    효과가 절반 이하로 떨어진다 (실측: VACUUM 전 1,755 buffers / 후 913). autovacuum 상태가
--    성능에 직결되므로, 느려졌다면 EXPLAIN 의 `Heap Fetches` 를 먼저 확인할 것.
--
-- 기존 인덱스와 중복이 아니다 (V15 에서 중복 인덱스를 정리한 이력이 있어 명시한다):
--   quarter_workouts_match_id_quarter_number_key (match_id, quarter_number) UNIQUE
--     → 제약 조건용. duration_seconds·avg_heart_rate 를 담지 않아 Index Only Scan 불가.
--   idx_matches_user_played_at_id (user_id, played_at DESC, id DESC)
--     → 커서 페이지네이션용. DESC 정렬과 id 가 필요해 아래 인덱스로 대체할 수 없다.
--
-- 락: CREATE INDEX 는 대상 테이블에 SHARE 락을 잡는다 (읽기 가능, 쓰기 차단).
--     현재 prod 데이터 규모(경기 수십 건)에서는 즉시 끝나지만, 데이터가 커지면
--     CREATE INDEX CONCURRENTLY 를 검토한다 (Flyway 트랜잭션 밖 실행 설정 필요).

-- ② 쿼터 집계 — SUM(avg_heart_rate * duration_seconds), SUM(duration_seconds), COUNT(*)
CREATE INDEX idx_qw_match_covering
    ON quarter_workouts (match_id)
    INCLUDE (duration_seconds, avg_heart_rate);

-- ① 경기 집계 + 월별 — SUM/COUNT/MAX 가 읽는 컬럼 전부를 INCLUDE 한다.
-- played_at 은 월별 GROUP BY 에도 쓰이므로 키에 포함돼 있다.
CREATE INDEX idx_matches_user_played_covering
    ON matches (user_id, played_at)
    INCLUDE (total_distance_m, goals, assists, result, max_speed_kmh, sprint_count);
