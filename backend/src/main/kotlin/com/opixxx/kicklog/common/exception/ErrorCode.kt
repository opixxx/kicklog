package com.opixxx.kicklog.common.exception

import org.springframework.http.HttpStatus

enum class ErrorCode(
    val status: HttpStatus,
    val message: String,
) {
    AUTH_INVALID_TOKEN(HttpStatus.UNAUTHORIZED, "인증 토큰이 유효하지 않습니다"),
    AUTH_EXPIRED_TOKEN(HttpStatus.UNAUTHORIZED, "인증 토큰이 만료되었습니다"),
    AUTH_INVALID_APPLE_TOKEN(HttpStatus.UNAUTHORIZED, "Apple 토큰 검증에 실패했습니다"),
    AUTH_INVALID_KAKAO_TOKEN(HttpStatus.UNAUTHORIZED, "카카오 토큰 검증에 실패했습니다"),
    AUTH_INVALID_REFRESH(HttpStatus.UNAUTHORIZED, "Refresh token이 유효하지 않습니다"),
    AUTH_EXPIRED_REFRESH(HttpStatus.UNAUTHORIZED, "Refresh token이 만료되었습니다"),
    AUTH_REFRESH_REUSED(HttpStatus.UNAUTHORIZED, "이미 사용된 Refresh token입니다"),
    AUTH_REFRESH_NOT_OWNED(HttpStatus.FORBIDDEN, "본인 세션만 로그아웃할 수 있습니다"),
    USER_NOT_FOUND(HttpStatus.NOT_FOUND, "사용자를 찾을 수 없습니다"),
    VENUE_NOT_FOUND(HttpStatus.NOT_FOUND, "운동장을 찾을 수 없습니다"),
    VENUE_NOT_OWNED(HttpStatus.FORBIDDEN, "본인의 운동장이 아닙니다"),
    VENUE_NAME_DUPLICATE(HttpStatus.CONFLICT, "같은 이름의 운동장이 이미 있습니다"),
    EXTERNAL_APPLE_UNAVAILABLE(HttpStatus.BAD_GATEWAY, "Apple 서비스가 일시적으로 응답하지 않습니다"),
    EXTERNAL_KAKAO_UNAVAILABLE(HttpStatus.BAD_GATEWAY, "카카오 서비스가 일시적으로 응답하지 않습니다"),
    VALIDATION_FAILED(HttpStatus.BAD_REQUEST, "요청 값이 올바르지 않습니다"),
}
