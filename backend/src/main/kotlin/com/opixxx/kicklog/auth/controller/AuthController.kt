package com.opixxx.kicklog.auth.controller

import com.opixxx.kicklog.auth.dto.AppleSignInRequest
import com.opixxx.kicklog.auth.dto.KakaoSignInRequest
import com.opixxx.kicklog.auth.dto.RefreshRequest
import com.opixxx.kicklog.auth.dto.SignInResponse
import com.opixxx.kicklog.auth.dto.TokenResponse
import com.opixxx.kicklog.auth.entity.OAuthProvider
import com.opixxx.kicklog.auth.service.AppleIdentityVerifier
import com.opixxx.kicklog.auth.service.AuthService
import com.opixxx.kicklog.auth.service.KakaoOAuthClient
import com.opixxx.kicklog.common.security.KickLogPrincipal
import jakarta.validation.Valid
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/auth")
class AuthController(
    private val authService: AuthService,
    private val appleIdentityVerifier: AppleIdentityVerifier,
    private val kakaoOAuthClient: KakaoOAuthClient,
) {
    @PostMapping("/apple/signin")
    fun signInWithApple(@Valid @RequestBody request: AppleSignInRequest): SignInResponse {
        val userInfo = appleIdentityVerifier.verify(request.identityToken)
        return authService.signIn(
            provider = OAuthProvider.APPLE,
            providerUserId = userInfo.providerUserId,
            email = userInfo.email,
            displayNameHint = request.name ?: userInfo.displayName ?: "사용자",
        )
    }

    @PostMapping("/kakao/signin")
    fun signInWithKakao(@Valid @RequestBody request: KakaoSignInRequest): SignInResponse {
        val userInfo = kakaoOAuthClient.fetchUserInfo(request.kakaoAccessToken)
        return authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = userInfo.providerUserId,
            email = userInfo.email,
            displayNameHint = userInfo.displayName ?: "사용자",
        )
    }

    @PostMapping("/refresh")
    fun refresh(@Valid @RequestBody request: RefreshRequest): TokenResponse {
        return authService.refresh(request.refreshToken)
    }

    @PostMapping("/logout")
    fun logout(@AuthenticationPrincipal principal: KickLogPrincipal): ResponseEntity<Void> {
        authService.logout(principal.userId)
        return ResponseEntity.noContent().build()
    }

    @PostMapping("/logout/this-device")
    fun logoutThisDevice(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @Valid @RequestBody request: RefreshRequest,
    ): ResponseEntity<Void> {
        authService.logoutThisDevice(principal.userId, request.refreshToken)
        return ResponseEntity.noContent().build()
    }
}
