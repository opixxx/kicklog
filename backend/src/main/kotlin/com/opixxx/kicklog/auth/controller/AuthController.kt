package com.opixxx.kicklog.auth.controller

import com.opixxx.kicklog.auth.dto.KakaoSignInRequest
import com.opixxx.kicklog.auth.dto.RefreshRequest
import com.opixxx.kicklog.auth.dto.SignInResponse
import com.opixxx.kicklog.auth.dto.TokenResponse
import com.opixxx.kicklog.auth.service.AuthService
import jakarta.validation.Valid
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/auth")
class AuthController(
    private val authService: AuthService,
) {
    @PostMapping("/kakao/signin")
    fun signInWithKakao(@Valid @RequestBody request: KakaoSignInRequest): SignInResponse =
        authService.signInWithKakao(request.kakaoAccessToken)

    @PostMapping("/refresh")
    fun refresh(@Valid @RequestBody request: RefreshRequest): TokenResponse =
        authService.refresh(request.refreshToken)
}
