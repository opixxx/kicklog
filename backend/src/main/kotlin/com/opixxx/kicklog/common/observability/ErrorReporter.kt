package com.opixxx.kicklog.common.observability

/**
 * 서버 측 오류를 외부 에러 트래킹 시스템(Sentry)으로 전송하는 추상화.
 *
 * GlobalExceptionHandler 가 5xx·미처리 예외에 한해 호출한다 (4xx 비즈니스 예외는 제외).
 * 캡처를 인터페이스로 감싸 테스트에서 전송 여부를 검증할 수 있게 한다.
 */
fun interface ErrorReporter {
    fun report(throwable: Throwable)
}
