package com.opixxx.kicklog.common.logging

import jakarta.servlet.FilterChain
import org.slf4j.MDC
import org.springframework.mock.web.MockHttpServletRequest
import org.springframework.mock.web.MockHttpServletResponse
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * EXEC_PLAN 2026-06-10 audit-fixes P2-2 — TraceIdFilter.
 *
 * 요청마다 8자 hex traceId 를 MDC 에 넣고, 응답 완료 후 MDC 에서 제거하는지 검증한다.
 * (MDC 잔류 시 스레드 풀 재사용으로 다음 요청에 traceId 가 오염된다 — 누락 금지.)
 */
class TraceIdFilterTest {

    private val filter = TraceIdFilter()

    @AfterTest
    fun clearMdc() {
        MDC.clear()
    }

    @Test
    fun `필터 체인 실행 중에는 MDC 에 8자 hex traceId 가 존재한다`() {
        val request = MockHttpServletRequest("GET", "/matches")
        val response = MockHttpServletResponse()
        var capturedTraceId: String? = null

        val chain = FilterChain { _, _ ->
            capturedTraceId = MDC.get("traceId")
        }

        filter.doFilter(request, response, chain)

        assertNotNull(capturedTraceId)
        assertTrue(
            Regex("^[0-9a-f]{8}$").matches(capturedTraceId!!),
            "traceId 는 8자 hex 여야 한다: $capturedTraceId",
        )
    }

    @Test
    fun `응답 완료 후 MDC 에 traceId 가 잔류하지 않는다`() {
        val request = MockHttpServletRequest("GET", "/matches")
        val response = MockHttpServletResponse()
        val chain = FilterChain { _, _ -> /* no-op */ }

        filter.doFilter(request, response, chain)

        assertNull(MDC.get("traceId"))
    }

    @Test
    fun `체인에서 예외가 나도 MDC 의 traceId 는 정리된다`() {
        val request = MockHttpServletRequest("GET", "/matches")
        val response = MockHttpServletResponse()
        val chain = FilterChain { _, _ -> throw RuntimeException("downstream 실패") }

        runCatching<Unit> { filter.doFilter(request, response, chain) }

        assertNull(MDC.get("traceId"))
    }
}
