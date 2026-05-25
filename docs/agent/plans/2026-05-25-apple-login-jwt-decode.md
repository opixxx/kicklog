# EXEC_PLAN — apple-login-jwt-decode

| 항목 | 값 |
|---|---|
| Task | apple-login-jwt-decode |
| Type | fix |
| Branch | fix/apple-login-jwt-decode |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/apple-login-jwt-decode |
| Port | 9000 |
| 생성 시각 | 2026-05-25 21:16 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

> **단순화 + TDD 원칙**:
> - 본 템플릿은 GearShow의 8섹션을 KickLog용 **4섹션 + optional**로 축소 (Ralph: "계획은 일회용·짧게")
> - **테스트 케이스 섹션**을 통해 TDD 강제 — 구현 전에 테스트 케이스 명시
> - 30줄 미만의 작은 변경은 EXEC_PLAN 자체가 면제됨 (`enforce-plan.sh`)

## 1. 목표 (Goal)

Apple Sign-In identityToken 검증이 백엔드에서 `AppleJwtHeader` Jackson 역직렬화 오류로 실패하는 문제를 수정한다.
정상 Apple JWT header/payload는 Kotlin data class 생성자 설정에 의존하지 않고 안정적으로 읽어야 한다.

## 2. 접근 (Approach)

- `AppleIdentityVerifier`의 JWT header/payload decode 경로를 Jackson Kotlin 생성자 역직렬화에 의존하지 않도록 변경한다.
- API 계약, DB 스키마, iOS 요청 형식은 변경하지 않는다.
- Apple JWT의 `alg`, `iss`, `aud`, `exp`, `kid`, 서명 검증 규칙은 유지한다.

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**

### Happy Path
- [x] 유효한 Apple JWT와 JWKS가 주어지면 `providerUserId`와 `email`을 반환한다.

### Unhappy Path (예외)
- [x] JWT 조각 수가 3개가 아니면 `AUTH_INVALID_APPLE_TOKEN`을 반환한다.

### Edge Cases
- [x] 만료된 JWT는 `AUTH_INVALID_APPLE_TOKEN`을 반환한다.

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew test --tests com.opixxx.kicklog.auth.service.AppleIdentityVerifierTest`
- 백엔드: `cd backend && ./gradlew test --tests 'com.opixxx.kicklog.auth.service.*' --tests 'com.opixxx.kicklog.common.security.*'`
- 백엔드: `cd backend && ./gradlew compileKotlin`
- 백엔드: `cd backend && ./gradlew check`
- iOS: 자동 검증 없음 (사용자가 Xcode 에서 수동 빌드)

### 시나리오 검증 (수동)
- iOS 시뮬레이터에서 Apple 로그인 후 백엔드가 500 없이 로그인 응답을 반환한다.

### 커버리지
- Apple JWT decode와 만료 경로를 단위 테스트로 고정한다.

### 검증 결과
- `./gradlew test --tests com.opixxx.kicklog.auth.service.AppleIdentityVerifierTest` 통과
- `./gradlew test --tests 'com.opixxx.kicklog.auth.service.*' --tests 'com.opixxx.kicklog.common.security.*'` 통과
- `./gradlew compileKotlin` 통과
- `./gradlew check`는 `FriendshipMigrationTest`의 Testcontainers/Docker 확인 단계에서 로컬 Docker 상태 영향으로 3분 이상 정체되어 중단

---

## (Optional) 위험도 / 롤백

Safe. API/DB 변경 없음.

## (Optional) 후속 / 관련 이슈

없음.

## (Optional) 학습 기록

Trigger: none

---

## TDD 작업 흐름

```
1. 위의 "3. 테스트 케이스" 섹션 채우기 (사용자가 결정)
2. 🔴 RED:
   - test-writer agent에게 위 케이스를 코드로 변환 위임
   - ./gradlew test (or Cmd+U) → 모두 실패 확인
3. 🟢 GREEN:
   - 한 케이스씩 최소 구현
   - 테스트 통과
4. 🔵 REFACTOR:
   - 중복 제거, 메서드 분리, 네이밍 정리
   - 테스트 여전히 통과
5. 다음 케이스 반복
6. 모든 케이스 통과 → "4. 검증" 섹션의 명령 실행
7. self-heal/Critical/누락 테스트가 있었으면 학습 기록 판단
8. PR 생성 (/pr-guide)
```

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
