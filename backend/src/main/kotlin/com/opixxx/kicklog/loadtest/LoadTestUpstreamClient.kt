package com.opixxx.kicklog.loadtest

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component
import org.springframework.web.client.RestClient
import org.springframework.web.client.RestClientException

/** mock upstream 의 지연 응답 본문 — 역직렬화 비용까지 측정에 포함시키기 위해 실제로 파싱한다. */
data class UpstreamEcho(
    val delayedMs: Int = 0,
    val pid: Int = 0,
)

/**
 * mock 외부 의존 호출 — **동기 블로킹**이다. 호출 스레드는 응답까지 점유된다.
 *
 * 이 점유가 시나리오 1 의 측정 대상이다: 동시성 = 주입률 × 지연 이므로
 * 지연이 길어지면 필요한 스레드 수가 비례해 늘고, Tomcat 스레드 상한에서 처리량이 꺾인다.
 */
@Component
@Profile("loadtest & !prod")
class LoadTestUpstreamClient(
    @Qualifier("loadTestUpstreamRestClient") private val restClient: RestClient,
) {

    fun fetchWithDelay(delayMs: Int): UpstreamEcho {
        return try {
            restClient.get()
                .uri { builder -> builder.path("/delay").queryParam("ms", delayMs).build() }
                .retrieve()
                .body(UpstreamEcho::class.java)
                ?: throw KickLogException(ErrorCode.EXTERNAL_UPSTREAM_UNAVAILABLE)
        } catch (exception: RestClientException) {
            // upstream 장애·타임아웃을 502 로 변환한다. 스택이나 내부 URL 을 응답에 노출하지 않는다
            // (운영 인증 경로가 EXTERNAL_APPLE_UNAVAILABLE 로 감싸는 것과 같은 규약).
            throw KickLogException(ErrorCode.EXTERNAL_UPSTREAM_UNAVAILABLE, cause = exception)
        }
    }
}
