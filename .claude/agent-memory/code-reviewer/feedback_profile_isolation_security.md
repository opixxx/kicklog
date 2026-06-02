---
name: profile-isolation-security
description: loadtest/디버그 전용 엔드포인트의 보안 경계는 @Profile 격리 + 실제 배포 프로파일명 일치로 판정한다
metadata:
  type: feedback
---

`@Profile("loadtest")` 같은 프로파일 격리로 prod 노출을 막는 빈(인증 우회 토큰 발급, 대량 시드 등)을 리뷰할 때는 **격리 주장 자체를 코드로만 믿지 말고 배포 설정과 대조**해 판정한다.

**Why:** loadtest-api-harness PR 에서 `/loadtest/token`(JWT 우회 발급) + SecurityConfig `/loadtest/**` permitAll 이 추가됨. permitAll 만 보면 Critical 후보지만, 핸들러가 `@Profile("loadtest")` 라 prod 에 빈 미등록 → 라우트 매핑 부재 → 404 (permitAll 은 매칭할 핸들러가 없어 무해). 안전성의 근거는 "prod 가 실제로 loadtest 프로파일을 활성화하지 않는다"는 사실이다.

**How to apply:**
- 실제 prod 배포가 어떤 프로파일을 켜는지 확인: `infra/docker-compose.prod.yml` 의 `SPRING_PROFILES_ACTIVE: prod` (loadtest 미포함 → 격리 성립).
- 격리 회귀 테스트가 `@ActiveProfiles("prod")` 로 404 를 검증하는지 + 그 프로파일명이 실제 배포 프로파일명과 **정확히 일치**하는지 확인 (이름 불일치 시 false confidence).
- SecurityConfig 가 프로파일 무관 항상 로드되어 permitAll 이 남아도, 핸들러 빈이 프로파일 격리면 안전 (라우트 부재가 1차 방어선, permitAll 은 무관).
- 잔여 리스크로 남길 것: 운영자가 실수로 `SPRING_PROFILES_ACTIVE=prod,loadtest` 동시 활성화 시 노출됨 — 배포 가드(런타임 fail-fast 등)는 후속 권장사항.
