# KickLog Backend

Spring Boot 4 + Kotlin 백엔드. iOS 클라이언트의 사용자 계정·친구 관계·경기 데이터 동기화를 담당한다.

## 책임
- Sign in with Apple 인증 + JWT 발급
- 사용자 계정 관리 (사용자명, 표시 이름, 프라이버시 토글)
- 1:1 친구 관계 그래프 + 초대 링크
- 경기 데이터 영속화 (메타데이터·집계 지표·쿼터 매핑)
- 친구 데이터 read API (권한 검증 포함)

## 명시적으로 안 하는 일
- HealthKit 원본 시계열 저장 (iOS 로컬 처리, 집계 지표만 업로드)
- 스프린트 계산·smoothing·쿼터 통계 (iOS에서 처리)

## 로컬 개발

```bash
# 1. PostgreSQL 실행
cd ../infra && docker compose up -d postgres

# 2. 백엔드 실행
./gradlew bootRun
# → http://localhost:8080/ (HealthCheck)
# → http://localhost:8080/actuator/health
```

### 환경 변수 (기본값 있음)
- `DB_URL` (기본 `jdbc:postgresql://localhost:5432/kicklog`)
- `DB_USERNAME` / `DB_PASSWORD` (기본 `kicklog` / `kicklog`)
- `SERVER_PORT` (기본 `8080`)
- `JWT_SECRET` (운영 시 필수, 32자 이상)
- Sign in with Apple 관련: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`

## 마이그레이션

Flyway로 관리. `src/main/resources/db/migration/V{n}__{name}.sql` 형식.

현재 V1은 placeholder. 실제 스키마는 **ADR-0003** 결정 후 V2부터 작성.

## 빌드 / 테스트

```bash
./gradlew build       # 컴파일 + 테스트
./gradlew test        # 테스트만
./gradlew bootJar     # 실행 가능 JAR
```
