import SwiftUI
import SwiftData

// 온보딩 4페이지 — TabView paging 으로 구현.
// 1) KickLog 로고/태그라인 → 2) Watch 안내 → 3) Apple/Kakao 로그인 → 4) HealthKit 권한
struct OnboardingScreen: View {
    @State private var currentPage: Int = 0
    var onComplete: () -> Void = {}

    var body: some View {
        ZStack {
            KLTokens.bg.ignoresSafeArea()

            TabView(selection: $currentPage) {
                OnboardPage1(currentPage: $currentPage).tag(0)
                OnboardPage2(currentPage: $currentPage).tag(1)
                OnboardPage3(currentPage: $currentPage).tag(2)
                OnboardPage4(onComplete: onComplete).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 건너뛰기 (전역, page 4 에서는 숨김)
            if currentPage < 3 {
                VStack {
                    HStack {
                        Spacer()
                        Button("건너뛰기", action: onComplete)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(KLTokens.textSec)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Page 1: 로고 + 태그라인

private struct OnboardPage1: View {
    @Binding var currentPage: Int

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 0) {
                // KickLog 앱 아이콘 (Assets.xcassets/KickLogIcon — 앱 아이콘과 동일 비주얼).
                Image("KickLogIcon")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 124, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: KLTokens.pitch.opacity(0.35), radius: 20, x: 0, y: 16)
                    .padding(.bottom, 28)

                Text("KickLog")
                    .font(.system(size: 38, weight: .heavy))
                    .tracking(-1.2)
                    .foregroundStyle(KLTokens.text)
                    .padding(.bottom, 10)

                Text("조기축구 데이터를 기록하다")
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(KLTokens.textSec)
                    .lineSpacing(4)
            }
            Spacer()
            bottomControls(currentPage: $currentPage, totalPages: 4)
        }
    }
}

// MARK: - Page 2: Watch 안내 (쿼터 단위 사용법 + Soccer 강조)

private struct OnboardPage2: View {
    @Binding var currentPage: Int

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 24)
                    WatchIllustration()
                        .padding(.bottom, 16)

                    Text("워치가 모든 걸 기록해요")
                        .font(.system(size: 24, weight: .heavy))
                        .tracking(-0.8)
                        .foregroundStyle(KLTokens.text)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 14)

                    SoccerWarningBox()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    QuarterUsageSteps()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            bottomControls(currentPage: $currentPage, totalPages: 4)
        }
    }
}

// ⚠ 주의 박스 — 워치에서 Soccer 외 종목은 KickLog 가 import 하지 않음 (WorkoutImporter.predicateForWorkouts(.soccer)).
private struct SoccerWarningBox: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KLIcon(name: "exclamationmark.triangle.fill", size: 18, color: KLTokens.amber)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                (Text("반드시 ") + Text("Soccer (축구)").bold() + Text(" 선택"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KLTokens.text)
                Text("다른 종목(Running 등)은 KickLog 에 잡히지 않아요.")
                    .font(.system(size: 12))
                    .foregroundStyle(KLTokens.textSec)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            (scheme == .dark ? KLTokens.amber.opacity(0.12) : Color(hex: 0xFFF8E6)),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(KLTokens.amber.opacity(0.35), lineWidth: 1)
        )
    }
}

// 1~4 쿼터 단위 사용법. 한 경기 = 1~4개의 Soccer Workout 이라는 모델을 단계로 풀어냄.
private struct QuarterUsageSteps: View {
    private let steps: [(title: String, sub: String)] = [
        ("워치 운동 앱 → Soccer 선택", "쿼터를 시작할 때마다 새 운동으로 시작합니다"),
        ("쿼터 시작 시 시작, 쿼터 끝나면 정지", "출전한 쿼터만 기록하면 됩니다"),
        ("다음 쿼터마다 다시 Soccer 새 운동", "1~4쿼터 반복 — 쿼터당 1개의 운동"),
        ("경기 후 폰을 열면 자동으로 묶임", "같은 날·연속된 쿼터를 한 경기로 인식합니다"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(KLTokens.pitch).frame(width: 24, height: 24)
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(KLTokens.text)
                        Text(step.sub)
                            .font(.system(size: 12))
                            .foregroundStyle(KLTokens.textSec)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) {
                    if index != steps.count - 1 {
                        Rectangle()
                            .fill(KLTokens.sep)
                            .frame(height: 0.5)
                            .padding(.leading, 50)
                    }
                }
            }
        }
        .background(KLTokens.bgElev, in: RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    }
}

// iPhone + Watch 일러스트
private struct WatchIllustration: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // iPhone shape
            VStack(spacing: 8) {
                KLIcon(name: "soccerball.inverse", size: 48, color: KLTokens.pitch)
                Text("KickLog")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(KLTokens.text)
            }
            .frame(width: 110, height: 200)
            .background(scheme == .dark ? Color(hex: 0x1C1C1E) : .white,
                        in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(scheme == .dark ? Color(hex: 0x2C2C2E) : Color(hex: 0xE5E5EA), lineWidth: 2)
            )
            .overlay(alignment: .top) {
                // dynamic island
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black)
                    .frame(width: 44, height: 12)
                    .padding(.top, 7)
            }

            // Watch shape (오버레이)
            ZStack {
                VStack(spacing: 4) {
                    KLIcon(name: "soccerball.inverse", size: 26, color: .white)
                    Text("23:14")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("Q2 · 진행 중")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: 64, height: 84)
                .background(KLTokens.pitch, in: RoundedRectangle(cornerRadius: 12))
            }
            .frame(width: 88, height: 108)
            .background(.black, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(scheme == .dark ? Color(hex: 0x48484A) : Color(hex: 0x1A1A1A), lineWidth: 4)
            )
            .offset(x: 60, y: 50)
        }
        .frame(width: 240, height: 240)
    }
}

// MARK: - Page 3: 로그인 (Apple / Kakao)

private struct OnboardPage3: View {
    @Binding var currentPage: Int
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var users: [User]
    @State private var signInErrorMessage: String?
    @State private var isSigningIn: Bool = false
    @State private var showDeletedAccountRecovery: Bool = false

    // Apple HIG — 라이트 UI 는 검정 버튼 + 흰 글자, 다크 UI 는 흰 버튼 + 검정 글자.
    // 기존 검정 고정은 다크모드에서 배경(KLTokens.bg)과 동일해 버튼 경계가 사라지는 문제가 있었음.
    private var appleButtonBackground: Color { scheme == .dark ? .white : .black }
    private var appleButtonForeground: Color { scheme == .dark ? .black : .white }

    var body: some View {
        VStack {
            Spacer().frame(height: 30)
            OnboardingPlayerIllustration()
                .padding(.bottom, 22)

            Text("시작하기")
                .font(.system(size: 28, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(KLTokens.text)
            Text("처음이라면 이 화면에서 자동으로 가입됩니다")
                .font(.system(size: 14))
                .foregroundStyle(KLTokens.textSec)
                .padding(.top, 8)

            VStack(spacing: 12) {
                Button(action: handleAppleSignIn) {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView().tint(appleButtonForeground)
                        } else {
                            KLIcon(name: "apple.logo", size: 20, color: appleButtonForeground)
                            Text("Apple로 시작하기")
                                .font(.system(size: 17, weight: .semibold))
                                .tracking(-0.3)
                                .foregroundStyle(appleButtonForeground)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(appleButtonBackground, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)

                Button(action: handleKakaoSignIn) {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView().tint(Color(hex: 0x3C1E1E))
                        } else {
                            KLIcon(name: "kakao.bubble", size: 20, color: Color(hex: 0x3C1E1E))
                            Text("카카오로 시작하기")
                                .font(.system(size: 17, weight: .semibold))
                                .tracking(-0.3)
                                .foregroundStyle(Color(hex: 0x3C1E1E))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(hex: 0xFEE500), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .alert("로그인 실패", isPresented: Binding(
                get: { signInErrorMessage != nil },
                set: { if !$0 { signInErrorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { signInErrorMessage = nil }
            } message: {
                Text(signInErrorMessage ?? "")
            }
            .alert("삭제 대기 계정", isPresented: $showDeletedAccountRecovery) {
                Button("로그아웃", role: .cancel) { clearSignedInUser() }
                Button("복구") { recoverDeletedAccount() }
            } message: {
                Text("계정 삭제를 취소하고 다시 사용할 수 있습니다.")
            }

            Spacer()

            // 법적 링크
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("개인정보 처리방침")
                        .underline()
                    Text("·")
                    Text("이용약관")
                        .underline()
                }
                .font(.system(size: 12))
                .foregroundStyle(KLTokens.textTer)

                KLPageDots(index: 2)
            }
            .padding(.bottom, 50)
        }
    }
}

// MARK: - Page 3 helpers

private extension OnboardPage3 {
    func handleAppleSignIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                _ = try await AuthService.shared.signInWithApple(modelContext: modelContext)
                try await continueAfterSignIn()
            } catch {
                signInErrorMessage = error.localizedDescription
            }
        }
    }

    func handleKakaoSignIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                _ = try await AuthService.shared.signInWithKakao(modelContext: modelContext)
                try await continueAfterSignIn()
            } catch {
                signInErrorMessage = error.localizedDescription
            }
        }
    }

    func continueAfterSignIn() async throws {
        do {
            _ = try await UserService.shared.fetchMe(into: modelContext)
            withAnimation { currentPage += 1 }
        } catch let apiError as APIError where apiError.isUserDeleted {
            showDeletedAccountRecovery = true
        }
    }

    func recoverDeletedAccount() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                _ = try await UserService.shared.cancelDeletion(into: modelContext)
                showDeletedAccountRecovery = false
                withAnimation { currentPage += 1 }
            } catch {
                signInErrorMessage = error.localizedDescription
            }
        }
    }

    func clearSignedInUser() {
        AuthTokenStore.shared.clear()
        for user in users {
            modelContext.delete(user)
        }
        modelContext.saveOrLog(caller: "OnboardingScreen.clearSignedInUser")
    }
}

private extension APIError {
    var isUserDeleted: Bool {
        if case .server(status: 410, let body, _) = self {
            return body?.code == "USER_DELETED"
        }
        return false
    }
}

// Page 3 일러스트 — figure.soccer SF Symbol + pitch 그라디언트.
// 가입 시작 시점에 "사람이 뛰는 활동" 메타포 — Page 1(로고) / Page 2(워치) 와 다양성.
private struct OnboardingPlayerIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [KLTokens.pitch, KLTokens.pitchDeep],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 160, height: 160)
                .shadow(color: KLTokens.pitch.opacity(0.35), radius: 24, x: 0, y: 14)

            Image(systemName: "figure.soccer")
                .font(.system(size: 88, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Page 4: 건강 데이터 권한

private struct OnboardPage4: View {
    var onComplete: () -> Void

    private let permissions: [(label: String, sub: String)] = [
        ("운동 (Workout)", "경기 시작·종료 시간"),
        ("심박수", "평균/최고 심박"),
        ("이동거리", "쿼터별 거리"),
        ("활성 에너지", "칼로리 소모"),
        ("달리기 속도", "평균/최고 속도"),
        ("운동 경로 (GPS)", "히트맵"),
    ]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            Spacer().frame(height: 30)
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(scheme == .dark ? Color(hex: 0xFF6B6B).opacity(0.16) : Color(hex: 0xFFEDEB))
                        .frame(width: 72, height: 72)
                    KLIcon(name: "heart.fill", size: 40, color: Color(hex: 0xFF3B30))
                }

                Text("건강 데이터 권한이 필요해요")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.7)
                    .foregroundStyle(KLTokens.text)
                    .multilineTextAlignment(.center)

                (Text("거리, 심박수, GPS 등 ")
                 + Text("6").font(.system(size: 14, weight: .bold)).foregroundColor(KLTokens.text)
                 + Text("가지 데이터로 경기 리포트를 만듭니다."))
                    .font(.system(size: 14))
                    .foregroundStyle(KLTokens.textSec)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            VStack(spacing: 0) {
                ForEach(Array(permissions.enumerated()), id: \.offset) { index, perm in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(KLTokens.pitch).frame(width: 26, height: 26)
                            KLIcon(name: "checkmark", size: 14, color: .white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(perm.label)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(KLTokens.text)
                            Text(perm.sub)
                                .font(.system(size: 12))
                                .foregroundStyle(KLTokens.textSec)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) {
                        if index != permissions.count - 1 {
                            Rectangle()
                                .fill(KLTokens.sep)
                                .frame(height: 0.5)
                                .padding(.leading, 54)
                        }
                    }
                }
            }
            .background(KLTokens.bgElev)
            .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
            .padding(.horizontal, 16)
            .padding(.top, 20)

            Text("데이터는 폰에 저장되고\n친구가 볼 수 있게 동기화돼요")
                .font(.system(size: 12))
                .foregroundStyle(KLTokens.textTer)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 14)
                .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 16) {
                Button(action: requestHealthAuthorization) {
                    Text("권한 허용하기")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)   // 온보딩 버튼 높이 통일 (OAuth 버튼과 동일)
                        .background(KLTokens.pitch, in: RoundedRectangle(cornerRadius: KLTokens.radiusBtn))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                KLPageDots(index: 3)
            }
            .padding(.bottom, 50)
        }
    }

    // 실제 HealthKit 권한 다이얼로그 표시. 결과와 무관하게 onComplete (사용자가 거부해도 앱 진입 — 설정에서 다시 켤 수 있음).
    private func requestHealthAuthorization() {
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
            } catch {
                // 시뮬레이터에서 HealthKit 미지원이거나 거부됨 — MVP 는 그래도 앱 진입 허용
                print("HealthKit authorization failed: \(error.localizedDescription)")
            }
            await MainActor.run { onComplete() }
        }
    }
}

// MARK: - 공통 하단 컨트롤 (다음 버튼 + dots)

@ViewBuilder
private func bottomControls(currentPage: Binding<Int>, totalPages: Int) -> some View {
    VStack(spacing: 16) {
        Button(action: {
            withAnimation { currentPage.wrappedValue += 1 }
        }) {
            Text("다음")
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)   // 온보딩 버튼 높이 통일 (OAuth 버튼과 동일)
                .background(KLTokens.pitch, in: RoundedRectangle(cornerRadius: KLTokens.radiusBtn))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)

        KLPageDots(index: currentPage.wrappedValue, total: totalPages)
    }
    .padding(.bottom, 50)
}

// MARK: - Page Indicator

struct KLPageDots: View {
    let index: Int
    var total: Int = 4

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == index ? KLTokens.pitch : KLTokens.textQuat)
                    .frame(width: i == index ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: index)
            }
        }
    }
}

#Preview("Onboarding — Light") {
    OnboardingScreen()
}

#Preview("Onboarding — Dark") {
    OnboardingScreen().preferredColorScheme(.dark)
}
