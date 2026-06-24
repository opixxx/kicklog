package com.opixxx.kicklog.common.observability

import com.opixxx.kicklog.common.logging.MdcKeys
import io.sentry.Sentry
import org.slf4j.LoggerFactory
import org.slf4j.MDC
import org.springframework.stereotype.Component

/**
 * Sentry 로 예외를 전송하는 ErrorReporter 구현.
 *
 * DSN 이 비어 있으면(local/test) Sentry SDK 가 자동으로 비활성화되어 no-op 으로 동작하므로
 * 별도 분기가 필요 없다. 요청별 traceId(MDC)를 이벤트 태그로 붙여 서버 로그와 상관관계를 맞춘다.
 */
@Component
class SentryErrorReporter : ErrorReporter {

    private val logger = LoggerFactory.getLogger(javaClass)

    override fun report(throwable: Throwable) {
        // 에러 트래킹 전송 실패가 정상 에러 응답 경로를 절대 막지 않도록 모든 예외를 삼킨다.
        runCatching {
            val traceId = MDC.get(MdcKeys.TRACE_ID)
            Sentry.captureException(throwable) { scope ->
                if (traceId != null) {
                    scope.setTag(MdcKeys.TRACE_ID, traceId)
                }
            }
        }.onFailure { logger.warn("Sentry 전송 실패", it) }
    }
}
