# KickLog iOS

iOS 앱. 사용자는 이 폴더에 Xcode 프로젝트를 직접 생성한다.

## Xcode 프로젝트 생성 가이드 (수동, 1회만)

1. **Xcode 열기** → `File` → `New` → `Project…` (`⇧⌘N`)
2. **Template**: `iOS` 탭 → `App` 선택 → `Next`
3. **Options**:
   - **Product Name**: `KickLog`
   - **Team**: 본인 Apple Developer 계정
   - **Organization Identifier**: `com.opixxx`
   - **Bundle Identifier**: `com.opixxx.kicklog` (자동 생성됨)
   - **Interface**: `SwiftUI`
   - **Language**: `Swift`
   - **Storage**: `SwiftData`
   - **Include Tests**: ☑ (체크)
4. **저장 위치**: 본 디렉토리(`~/Developer/kicklog/ios/`) 선택. **Create Git repository**는 ☐ (체크 해제 — 모노레포 루트에서 git 관리)
5. 프로젝트 생성 완료

## 생성 후 설정

### Info / 권한 (Info.plist)
- `NSHealthShareUsageDescription` (HealthKit 읽기)
  ```
  축구 경기 데이터를 분석해 거리·속도·심박수·쿼터별 체력 변화 리포트를 제공합니다.
  ```
- `NSHealthUpdateUsageDescription` (안 쓰면 생략 가능)
- `NSLocationWhenInUseUsageDescription` (운동장 자동 인식용 — 첫 라벨링 시점에 요청)
  ```
  자주 가시는 운동장을 자동으로 인식해 매번 입력하지 않아도 되도록 합니다.
  ```

### Capabilities (Signing & Capabilities)
- ☑ **HealthKit**
- ☑ **Sign in with Apple**
- ☑ **Background Modes** → ☑ Background fetch, ☑ Remote notifications (v1.1)

### Deployment Target
- **iOS 26.4** (Xcode 기본값 그대로. 본인+팀원 모두 최신 폰 가정)

### 추가 의존성 (SPM, 필요 시점에)
- (MVP에선 외부 의존성 거의 없음 — Apple 표준 프레임워크로 충분)
- 향후 후보:
  - `Alamofire` (또는 URLSession 직접) — 백엔드 API 호출
  - `KeychainAccess` — JWT 안전 저장

## 폴더 구조 (Xcode 그룹)

```
KickLog/
├── App/                  앱 진입점, 온보딩 4페이지
├── Models/               SwiftData @Model 엔티티, 도메인 타입
├── Features/
│   ├── Games/            경기 탭, 라벨링 화면, 한 경기 리포트
│   ├── Season/           시즌 탭, 카드 6개
│   ├── Friends/          친구 탭, 친구 추가, 친구 리포트
│   └── Settings/         설정 탭
├── Services/
│   ├── HealthKitService  HealthKit 권한 + 워크아웃 읽기 + Observer Query
│   ├── LocationService   CoreLocation, 운동장 매칭
│   ├── APIClient         백엔드 통신
│   └── AuthService       Sign in with Apple + JWT 관리
├── Analytics/            스프린트 계산, 쿼터별 통계 (도메인 로직)
├── Components/           재사용 UI (BarChartCard, MetricBadge 등)
└── Resources/            Assets.xcassets, Localizable.strings
```

## 첫 실행 흐름 (구현 예정)
1. 온보딩 4페이지 (앱 소개 → 워치 가이드 → Sign in with Apple → HealthKit 권한)
2. 메인 탭바 — 경기 / 시즌 / 친구 / 설정
3. HealthKit Observer Query 등록 → 백그라운드 자동 import
