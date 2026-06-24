package com.opixxx.kicklog.common.observability

import io.sentry.Sentry
import jakarta.annotation.PostConstruct
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Configuration

/**
 * Sentry SDK 수동 초기화.
 *
 * Sentry 8.x 의 Spring Boot starter 는 Spring Boot 4(Spring Framework 7)를 아직 지원하지 않아
 * (제거된 RestClientCustomizer 참조로 autoconfiguration 부팅 실패), 코어 의존성만 쓰고 여기서 직접 init 한다.
 * 우리는 GlobalExceptionHandler 에서 5xx 만 명시적으로 캡처하므로 starter 의 자동 통합이 불필요하다.
 *
 * DSN 이 비어 있으면 init 자체를 건너뛰어 SDK 가 비활성(no-op)이 된다 — local/test 안전.
 */
@Configuration
class SentryConfig(
    @param:Value("\${sentry.dsn:}") private val dsn: String,
    @param:Value("\${sentry.environment:local}") private val environment: String,
    @param:Value("\${sentry.release:}") private val release: String,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @PostConstruct
    fun init() {
        if (dsn.isBlank()) {
            logger.info("SENTRY_DSN 미설정 — Sentry 에러 트래킹 비활성화")
            return
        }
        Sentry.init { options ->
            options.dsn = dsn
            options.environment = environment
            if (release.isNotBlank()) {
                options.release = release
            }
            // PII(JWT·카카오·이메일·헤더) 비전송 — 개인정보 보호.
            options.isSendDefaultPii = false
            // 성능 트레이싱 미사용 — 에러 트래킹 목적만 (무료 티어 quota 보호).
            options.tracesSampleRate = 0.0
        }
        logger.info("Sentry 에러 트래킹 활성화 (environment={})", environment)
    }
}
