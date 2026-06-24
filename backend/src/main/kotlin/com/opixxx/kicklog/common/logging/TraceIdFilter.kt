package com.opixxx.kicklog.common.logging

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.slf4j.MDC
import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import java.util.concurrent.ThreadLocalRandom

/**
 * 요청마다 8자 hex traceId 를 생성해 MDC 에 넣고, 응답 완료 후 제거한다 (P2-2).
 *
 * MDC 잔류 시 스레드 풀 재사용으로 다음 요청 로그가 오염되므로 finally 에서 반드시 제거한다.
 * GlobalExceptionHandler 가 MDC 의 traceId 를 읽어 ErrorResponse.traceId 에 채운다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class TraceIdFilter : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        MDC.put(MdcKeys.TRACE_ID, generateTraceId())
        try {
            filterChain.doFilter(request, response)
        } finally {
            MDC.remove(MdcKeys.TRACE_ID)
        }
    }

    private fun generateTraceId(): String {
        val value = ThreadLocalRandom.current().nextInt()
        return "%08x".format(value)
    }
}
