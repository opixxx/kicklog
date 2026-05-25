import Foundation
import AuthenticationServices
import SwiftData

// Apple Sign-In 흐름 + 백엔드 `/auth/apple/signin` 호출 + Keychain 저장 + User @Model UPSERT.
// Kakao 는 별도 (SDK 의존) — E1 후속.
@MainActor
final class AuthService: NSObject {
    static let shared = AuthService()

    private let apiClient: any APIClient = URLSessionAPIClient()
    private let tokenStore: AuthTokenStore = .shared

    var isAuthenticated: Bool { tokenStore.isAuthenticated }

    // MARK: - Apple Sign-In

    // ASAuthorizationController 콜백을 async 로 wrap 한다.
    private var pendingContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func signInWithApple(modelContext: ModelContext) async throws -> User {
        let credential = try await requestAppleCredential()
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.appleNoIdentityToken
        }
        // Apple 은 최초 1회만 fullName 제공. 그 외엔 nil.
        let name = [credential.fullName?.familyName, credential.fullName?.givenName]
            .compactMap { $0 }
            .joined()
            .nilIfEmpty

        let response: SignInResponse = try await apiClient.post(
            "/auth/apple/signin",
            body: AppleSignInRequest(identityToken: identityToken, name: name)
        )

        tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return upsertLocalUser(from: response.user, into: modelContext)
    }

    private func requestAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Logout

    func logout(modelContext: ModelContext) async {
        guard let refreshToken = tokenStore.refreshToken else {
            tokenStore.clear()
            return
        }
        // /auth/logout 호출 후 실패해도 로컬은 정리 (fire-and-forget)
        do {
            let _: EmptyResponse = try await apiClient.post(
                "/auth/logout",
                body: LogoutRequest(refreshToken: refreshToken)
            )
        } catch {
            print("AuthService.logout 백엔드 호출 실패 — \(error). 로컬 정리만 진행.")
        }
        tokenStore.clear()
    }

    // MARK: - User UPSERT (ADR-0004 D2 — SwiftData @Model 갱신)

    private func upsertLocalUser(from dto: UserDTO, into context: ModelContext) -> User {
        let serverId = dto.id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.displayName = dto.displayName
            existing.email = dto.email
            existing.hideHeartRate = dto.hideHeartRate
            existing.lastSyncedAt = .now
            try? context.save()
            return existing
        }
        let user = User(
            serverId: dto.id,
            displayName: dto.displayName,
            email: dto.email,
            hideHeartRate: dto.hideHeartRate,
            createdAt: .now,
            lastSyncedAt: .now
        )
        context.insert(user)
        try? context.save()
        return user
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            defer { self.pendingContinuation = nil }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self.pendingContinuation?.resume(throwing: AuthError.appleUnknownCredential)
                return
            }
            self.pendingContinuation?.resume(returning: credential)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            defer { self.pendingContinuation = nil }
            self.pendingContinuation?.resume(throwing: error)
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // 첫 active scene 의 window — MVP 1단말
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first { $0.isKeyWindow }
            ?? scene?.windows.first
            ?? ASPresentationAnchor()
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case appleNoIdentityToken
    case appleUnknownCredential

    var errorDescription: String? {
        switch self {
        case .appleNoIdentityToken: return "Apple identityToken 을 받지 못했습니다."
        case .appleUnknownCredential: return "Apple 자격 증명 형식이 예상과 다릅니다."
        }
    }
}

// MARK: - Helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
