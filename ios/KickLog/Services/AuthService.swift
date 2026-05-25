import Foundation
import AuthenticationServices
import KakaoSDKAuth
import KakaoSDKUser
import SwiftData

// Apple/Kakao Sign-In 흐름 + 백엔드 Auth API 호출 + Keychain 저장 + User @Model UPSERT.
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
        return User.upsert(from: response.user, into: modelContext)
    }

    // MARK: - Kakao Sign-In

    func signInWithKakao(modelContext: ModelContext) async throws -> User {
        let kakaoAccessToken = try await requestKakaoAccessToken()
        let response: SignInResponse = try await apiClient.post(
            "/auth/kakao/signin",
            body: KakaoSignInRequest(kakaoAccessToken: kakaoAccessToken)
        )

        tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return User.upsert(from: response.user, into: modelContext)
    }

    private func requestKakaoAccessToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let completion: (OAuthToken?, Error?) -> Void = { oauthToken, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let accessToken = oauthToken?.accessToken else {
                    continuation.resume(throwing: AuthError.kakaoNoAccessToken)
                    return
                }
                continuation.resume(returning: accessToken)
            }

            if UserApi.isKakaoTalkLoginAvailable() {
                UserApi.shared.loginWithKakaoTalk(completion: completion)
            } else {
                UserApi.shared.loginWithKakaoAccount(completion: completion)
            }
        }
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

    func logoutCurrentDevice() async {
        guard let refreshToken = tokenStore.refreshToken else {
            tokenStore.clear()
            return
        }

        // /auth/logout/this-device 호출 후 실패해도 로컬은 정리한다.
        do {
            let _: EmptyResponse = try await apiClient.post(
                "/auth/logout/this-device",
                body: LogoutRequest(refreshToken: refreshToken)
            )
        } catch {
            print("AuthService.logoutCurrentDevice 백엔드 호출 실패 — \(error). 로컬 정리만 진행.")
        }
        tokenStore.clear()
    }

    func logoutAllDevices() async {
        // /auth/logout 호출 후 실패해도 현재 기기의 로컬 토큰은 정리한다.
        do {
            let _: EmptyResponse = try await apiClient.post("/auth/logout")
        } catch {
            print("AuthService.logoutAllDevices 백엔드 호출 실패 — \(error). 로컬 정리만 진행.")
        }
        tokenStore.clear()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller _: ASAuthorizationController,
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
        controller _: ASAuthorizationController,
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
    nonisolated func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
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
    case kakaoNoAccessToken

    var errorDescription: String? {
        switch self {
        case .appleNoIdentityToken: return "Apple identityToken 을 받지 못했습니다."
        case .appleUnknownCredential: return "Apple 자격 증명 형식이 예상과 다릅니다."
        case .kakaoNoAccessToken: return "Kakao accessToken 을 받지 못했습니다."
        }
    }
}

// MARK: - Helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
