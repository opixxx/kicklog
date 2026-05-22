package com.opixxx.kicklog.auth.service

import org.springframework.http.HttpStatus

sealed class AuthException(
    val code: String,
    override val message: String,
    val status: HttpStatus,
) : RuntimeException(message)

class InvalidKakaoTokenException(message: String = "카카오 토큰 검증에 실패했습니다") :
    AuthException("AUTH_INVALID_KAKAO_TOKEN", message, HttpStatus.UNAUTHORIZED)

class ExternalKakaoException(message: String = "카카오 서비스가 일시적으로 응답하지 않습니다") :
    AuthException("EXTERNAL_KAKAO_UNAVAILABLE", message, HttpStatus.BAD_GATEWAY)

class InvalidRefreshTokenException(message: String = "refresh token이 올바르지 않습니다") :
    AuthException("AUTH_INVALID_REFRESH", message, HttpStatus.UNAUTHORIZED)

class ExpiredRefreshTokenException(message: String = "refresh token이 만료되었습니다") :
    AuthException("AUTH_EXPIRED_REFRESH", message, HttpStatus.UNAUTHORIZED)

class InvalidAccessTokenException(message: String = "access token이 올바르지 않습니다") :
    AuthException("AUTH_INVALID_TOKEN", message, HttpStatus.UNAUTHORIZED)
