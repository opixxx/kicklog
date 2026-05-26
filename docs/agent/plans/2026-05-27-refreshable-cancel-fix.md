# EXEC_PLAN — refreshable-cancel-fix

| 항목 | 값 |
|---|---|
| Task | refreshable-cancel-fix |
| Type | fix |
| Branch | fix/refreshable-cancel-fix |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/refreshable-cancel-fix |
| Port | 9000 |
| 생성 시각 | 2026-05-27 00:42 |
| 상태 | `done` |
| 개발 방식 | iOS UI 버그 수정 (백엔드 비대상) |

---

## 1. 목표

iOS 의 모든 리스트/상세 화면에서 **pull-to-refresh (`.refreshable`) 동작 시 `NSURLErrorDomain -999 cancelled`** 가 발생해 "알 수 없는 오류" 가 노출되는 문제를 수정한다. 다른 탭 갔다 오기(`.task` 첫 로드)는 정상 동작하므로 사용자가 운영 중 빈번히 마주치는 새로고침 경로만 망가져 있어 UX 손상이 크다.

또한 원인 진단을 위해 임시로 노출했던 `VenueListScreen` 의 디버그 에러 메시지와, 시뮬레이터 localhost HTTP 호출을 가능하게 한 `Info.plist` ATS 예외 추가를 한 PR 로 묶어 정리한다.

## 2. 접근

**원인**: SwiftUI `.refreshable { await load() }` 의 클로저는 ScrollView/View body 재평가 시 자체 Task 를 자동 cancel 한다. SwiftData `@Query` 의 데이터 변경, contentOffset 변동 등 사소한 트리거에도 URLSession 요청이 호스트 도달 전에 끊긴다.

**해결**: 모든 `.refreshable` 블록에서 load 호출을 **새 Task 로 wrapping** 해 view lifetime 과 분리한다.

```swift
// Before
.refreshable { await load() }

// After
.refreshable {
    _ = await Task { await load() }.value
}
```

`Task { ... }.value` 는 부모 task 의 cancellation 전파를 받지 않으므로, `.refreshable` 클로저가 cancel 돼도 내부 URLSession 호출은 살아남는다.

### 변경 파일

iOS 7개 화면 (`.refreshable` 사용처 전부):
- `ios/KickLog/Screens/VenueListScreen.swift`
- `ios/KickLog/Screens/MatchesScreen.swift`
- `ios/KickLog/Screens/SeasonScreen.swift`
- `ios/KickLog/Screens/FriendsScreen.swift`
- `ios/KickLog/Screens/FriendDetailScreen.swift`
- `ios/KickLog/Screens/FriendMatchDetailScreen.swift`
- `ios/KickLog/Screens/AddFriendSheet.swift`

부속 정리:
- `ios/KickLog/Screens/VenueListScreen.swift` — 진단용 임시 디버그 메시지(`디버그 [NSURLErrorDomain …]`) 원복
- `ios/KickLog-Info.plist` — `NSAppTransportSecurity > NSAllowsLocalNetworking = true` 추가 (시뮬레이터에서 `http://localhost:8080` 호출 가능하도록. 외부 HTTP 는 여전히 차단되는 가장 안전한 ATS 예외)

## 3. 테스트 케이스

iOS UI 변경 — 단위 테스트 비대상. **수동 검증**:

1. 시뮬레이터에서 KickLog 빌드 & 실행 (Clean Build 권장)
2. **각 탭 진입 시 `.task` 첫 로드 동작** — 정상 (변경 없음, 회귀 확인)
3. **각 탭/화면에서 pull-to-refresh** — `-999 cancelled` 발생하지 않고 정상 데이터 로드
   - 경기, 시즌, 친구, 친구 상세, 친구 경기 상세, 운동장 목록, 친구 추가 sheet
4. **운동장 검색** (`VenueSelectionScreen`) — 검색바 입력 시 `/places/search` 호출 → 카카오 결과 노출

## 4. 검증

### 자동
- 백엔드 변경 없음 — `./gradlew check` 비대상
- iOS Xcode 빌드: 사용자 (Cmd+B / Cmd+R)

### 수동
- 위 "테스트 케이스" 1~4 단계 시뮬레이터에서 실행

## (Optional) 위험도 / 롤백

Risk = **Caution**. SwiftUI `.refreshable` 의 Task lifecycle 변경이지만, `Task { ... }.value` 패턴은 iOS 15+ 표준이고 동작 변경은 "cancel 안 되게" 뿐이라 회귀 위험은 낮다. 롤백 시 `.refreshable { await load() }` 로 1줄씩 복원.

## (Optional) 후속

- `Info.plist` 의 ATS 예외는 **개발용**. 운영(EC2 + HTTPS) 도입 시 자동으로 무력화됨 (`NSAllowsLocalNetworking` 은 localhost·사설 IP 만 풀고 외부 HTTPS 는 이미 허용 기본값).
- `.refreshable` cancellation 이슈는 iOS 18+ SwiftUI 의 알려진 동작 — Apple 공식 가이드도 detached Task 패턴 권장. 향후 SwiftUI 가 개선되면 단순화 가능.
