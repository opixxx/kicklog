package com.opixxx.kicklog.common.exception

import com.opixxx.kicklog.common.observability.ErrorReporter
import org.slf4j.MDC
import org.springframework.mock.web.MockHttpServletRequest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * EXEC_PLAN 2026-06-10 audit-fixes P2-2 — 에러 응답 traceId (api-spec 계약).
 *
 * GlobalExceptionHandler 가 MDC 의 traceId 를 읽어 ErrorResponse.traceId 에 채우는지 검증한다.
 * (필드 추가만 — path 등 기존 필드는 유지. iOS APIErrorBody 가 이미 traceId? 디코딩.)
 */
class GlobalExceptionHandlerTraceIdTest {

    // 본 테스트는 4xx(MATCH_NOT_FOUND)만 다뤄 report 가 호출되지 않으므로 no-op 더블로 충분.
    private val handler = GlobalExceptionHandler(ErrorReporter { })

    @AfterTest
    fun clearMdc() {
        MDC.clear()
    }

    @Test
    fun `MDC 에 traceId 가 있으면 ErrorResponse traceId 에 채운다`() {
        MDC.put("traceId", "a1b2c3d4")
        val request = MockHttpServletRequest("GET", "/matches/999")
        val exception = KickLogException(ErrorCode.MATCH_NOT_FOUND)

        val response = handler.handleKickLogException(exception, request)

        val body = response.body!!
        assertEquals("MATCH_NOT_FOUND", body.code)
        assertEquals("/matches/999", body.path)
        assertEquals("a1b2c3d4", body.traceId)
    }

    @Test
    fun `MDC 에 traceId 가 없으면 ErrorResponse traceId 는 null 이다`() {
        val request = MockHttpServletRequest("GET", "/matches/999")
        val exception = KickLogException(ErrorCode.MATCH_NOT_FOUND)

        val response = handler.handleKickLogException(exception, request)

        assertNull(response.body!!.traceId)
    }
}
