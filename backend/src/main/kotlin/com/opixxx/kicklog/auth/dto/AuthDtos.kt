package com.opixxx.kicklog.auth.dto

import jakarta.validation.constraints.NotBlank

data class KakaoSignInRequest(
    @field:NotBlank(message = "카카오 access token을 입력해주세요")
    val kakaoAccessToken: String,
)

data class RefreshRequest(
    @field:NotBlank(message = "refresh token을 입력해주세요")
    val refreshToken: String,
)

data class TokenResponse(
    val accessToken: String,
    val refreshToken: String,
)

data class SignInResponse(
    val accessToken: String,
    val refreshToken: String,
    val user: AuthUserResponse,
)

data class AuthUserResponse(
    val id: Long,
    val displayName: String,
    val email: String?,
    val hideHeartRate: Boolean,
)
