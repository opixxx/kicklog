package com.opixxx.kicklog.auth.dto

import com.opixxx.kicklog.user.dto.UserResponse
import jakarta.validation.constraints.NotBlank

data class AppleSignInRequest(
    @field:NotBlank(message = "Apple identity token은 필수입니다")
    val identityToken: String,
    val name: String? = null,
)

data class KakaoSignInRequest(
    @field:NotBlank(message = "카카오 access token은 필수입니다")
    val kakaoAccessToken: String,
)

data class RefreshRequest(
    @field:NotBlank(message = "Refresh token은 필수입니다")
    val refreshToken: String,
)

data class SignInResponse(
    val accessToken: String,
    val refreshToken: String,
    val user: UserResponse,
)

data class TokenResponse(
    val accessToken: String,
    val refreshToken: String,
)
