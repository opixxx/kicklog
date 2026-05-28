-- 초대 링크 도메인 폐기 (P1 #4).
-- V12 의 users.display_name unique 도입으로 닉네임 검색만으로 친구 식별 가능 → 초대 링크 불필요.
-- 베타 사용자 ~2명이라 데이터 보존 불필요. DROP TABLE.
DROP TABLE IF EXISTS friend_invitations;
