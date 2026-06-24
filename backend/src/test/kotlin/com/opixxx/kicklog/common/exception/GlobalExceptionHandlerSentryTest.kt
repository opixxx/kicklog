package com.opixxx.kicklog.common.exception

import com.opixxx.kicklog.common.observability.ErrorReporter
import org.slf4j.MDC
import org.springframework.http.HttpStatus
import org.springframework.mock.web.MockHttpServletRequest
import org.springframework.web.server.ResponseStatusException
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * EXEC_PLAN 2026-06-23 sentry-error-tracking —
 * GlobalExceptionHandler 가 **5xx·미처리 예외만** ErrorReporter(Sentry)로 보내고,
 * 4xx 비즈니스 예외는 보내지 않는지 검증한다 (무료 티어 quota 절약 + 노이즈 제거).
 */
class GlobalExceptionHandlerSentryTest {

    private val reporter = RecordingErrorReporter()
    private val handler = GlobalExceptionHandler(reporter)
    private val request = MockHttpServletRequest("GET", "/some/path")

    @AfterTest
    fun clearMdc() {
        MDC.clear()
    }

    @Test
    fun `미처리 예외는 500 INTERNAL_ERROR 로 변환되고 Sentry 로 전송된다`() {
        MDC.put("traceId", "deadbeef")
        val exception = RuntimeException("예상치 못한 NPE 류")

        val response = handler.handleUnexpectedException(exception, request)

        val body = response.body!!
        assertEquals(500, response.statusCode.value())
        assertEquals("INTERNAL_ERROR", body.code)
        assertEquals("deadbeef", body.traceId)
        assertEquals(1, reporter.reported.size)
        assertSame(exception, reporter.reported.single())
    }

    @Test
    fun `5xx KickLogException 은 Sentry 로 전송된다`() {
        val exception = KickLogException(ErrorCode.EXTERNAL_KAKAO_UNAVAILABLE)

        val response = handler.handleKickLogException(exception, request)

        assertEquals(502, response.statusCode.value())
        assertEquals(1, reporter.reported.size)
    }

    @Test
    fun `INTERNAL_ERROR KickLogException 도 Sentry 로 전송된다`() {
        val exception = KickLogException(ErrorCode.INTERNAL_ERROR)

        handler.handleKickLogException(exception, request)

        assertEquals(1, reporter.reported.size)
    }

    @Test
    fun `4xx 비즈니스 예외는 Sentry 로 전송되지 않는다`() {
        val fourxxCodes = listOf(
            ErrorCode.USER_NOT_FOUND,        // 404
            ErrorCode.AUTH_INVALID_TOKEN,    // 401
            ErrorCode.MATCH_NOT_OWNED,       // 403
            ErrorCode.VALIDATION_FAILED,     // 400
            ErrorCode.DISPLAY_NAME_DUPLICATE, // 409
        )

        fourxxCodes.forEach { code ->
            handler.handleKickLogException(KickLogException(code), request)
        }

        assertTrue(reporter.reported.isEmpty(), "4xx 예외는 캡처되면 안 된다: ${reporter.reported}")
    }

    @Test
    fun `Spring MVC 4xx 표준 예외는 상태코드를 보존하고 Sentry 로 전송되지 않는다`() {
        // NoResourceFoundException(없는 경로) 등이 ResponseStatusException 계열 — 404 가 500 으로 둔갑하면 안 된다.
        val exception = ResponseStatusException(HttpStatus.NOT_FOUND, "리소스 없음")

        val response = handler.handleUnexpectedException(exception, request)

        assertEquals(404, response.statusCode.value())
        assertTrue(reporter.reported.isEmpty(), "Spring 4xx 는 캡처되면 안 된다")
    }

    @Test
    fun `Spring MVC 5xx 표준 예외는 Sentry 로 전송된다`() {
        val exception = ResponseStatusException(HttpStatus.BAD_GATEWAY, "업스트림 오류")

        val response = handler.handleUnexpectedException(exception, request)

        assertEquals(502, response.statusCode.value())
        assertEquals(1, reporter.reported.size)
    }

    /** 이 프로젝트 컨벤션(FakeKakaoLocalClient 등)에 맞춘 수제 테스트 더블. */
    private class RecordingErrorReporter : ErrorReporter {
        val reported = mutableListOf<Throwable>()

        override fun report(throwable: Throwable) {
            reported.add(throwable)
        }
    }
}
