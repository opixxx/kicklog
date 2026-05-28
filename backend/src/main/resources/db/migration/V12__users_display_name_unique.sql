-- 닉네임 유일 식별자 정책 도입 (P1 #5).
-- 활성 사용자(deleted_at IS NULL) 사이에서만 unique — 탈퇴자 닉네임은 재사용 허용.
-- 본인 닉네임 검색만으로 친구 식별 가능 → 초대 링크 도메인은 V13 에서 폐기.
CREATE UNIQUE INDEX uq_users_display_name_active
    ON users (display_name)
    WHERE deleted_at IS NULL;
