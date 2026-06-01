# KickLog

조기축구 경기 데이터 분석 앱. 애플워치 + HealthKit으로 측정한 데이터를 기반으로 쿼터별 체력 변화·스프린트·최고 속도 등 개인 경기 리포트를 제공한다.

## Repo 구조 (Monorepo)

```
kicklog/
├── docs/              # PRD, ADR, 설계 문서
│   ├── PRD.md         # 제품 요구 사항 정의
│   └── adr/           # Architecture Decision Records
├── ios/               # iOS 앱 (Swift + SwiftUI + SwiftData)
├── backend/           # 백엔드 (Kotlin + Spring Boot 3 + PostgreSQL)
└── infra/             # Docker, 배포 스크립트
```

## 기술 스택

### iOS
- Swift 5.10+ / SwiftUI / SwiftData
- HealthKit, CoreLocation, Swift Charts
- 최소 지원: iOS 18.0
- 번들 ID: `com.opixxx.kicklog`

### Backend
- Kotlin / Spring Boot 3.x / Java 17
- PostgreSQL 15
- Flyway, Spring Security (JWT)
- 호스팅 (예정): Railway / Fly.io

## 핵심 결정 (인터뷰 기반)

자세한 내용은 `docs/PRD.md`와 `docs/adr/0001-mvp-scope.md` 참조.

- **타깃**: 본인 + 축구팀 (iOS 사용자), 점진적으로 일반 공개
- **데이터 수집**: 조기축구 25분 × 4쿼터. 사용자가 출전 쿼터마다 Apple Watch의 Soccer 워크아웃 토글 → HealthKit 저장 → 앱이 사후에 읽기
- **친구 기능**: 1:1 양방향 친구 등록 (팀 단위는 v1.1+)
- **풋살**: v2 (MVP는 조기축구 only)
- **자체 watchOS 앱**: 없음 (Apple 기본 운동 앱 사용)

## 로컬 개발 시작 (예정)

```bash
# 1. 백엔드 DB
cd infra && docker compose up -d postgres

# 2. 백엔드 실행
cd backend && ./gradlew bootRun

# 3. iOS
open ios/KickLog.xcodeproj
```

## License

Private project. All rights reserved.
