package com.opixxx.kicklog.config

import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.client.SimpleClientHttpRequestFactory
import org.springframework.web.client.RestClient
import java.time.Duration

@Configuration
class RestClientConfig {

    /**
     * 외부 HTTP 호출용 공유 빌더 — **모든 외부 클라이언트는 이것을 주입받아 쓴다.**
     *
     * `RestClient.create()` 를 직접 쓰면 안 된다. 그 경우 타임아웃이 설정되지 않고,
     * `HttpURLConnection` 의 기본값은 **0 = 무한 대기**다. 외부가 거부(connection refused)하는 게
     * 아니라 **응답을 안 하고 물고 있으면** 호출 스레드가 영구 점유된다.
     *
     * 동기 블로킹 모델에서 이것은 전역 장애로 번진다 — Tomcat 스레드는 전 요청이 공유하므로,
     * 초당 1건의 로그인만 들어와도 200초면 스레드 200개가 모두 묶이고 그 순간 로그인뿐 아니라
     * 경기 목록·시즌 통계까지 멈춘다. **트래픽 규모와 무관한 사고다** (ADR-0017 D11).
     *
     * 프로퍼티 이름이 `kicklog.external-http.*` 인 이유: 원래 `kicklog.kakao.*` 였는데
     * Apple 인증도 이 빌더를 쓰게 되면서 이름이 사실과 어긋났다. 설정 이름이 거짓이면
     * 다음 사람이 "Apple 은 왜 Kakao 타임아웃을 쓰지?" 에서 멈춘다.
     */
    @Bean
    fun restClientBuilder(
        @Value("\${kicklog.external-http.connect-timeout-millis:2000}") connectTimeoutMillis: Long,
        @Value("\${kicklog.external-http.read-timeout-millis:3000}") readTimeoutMillis: Long,
    ): RestClient.Builder {
        val requestFactory = SimpleClientHttpRequestFactory().apply {
            setConnectTimeout(Duration.ofMillis(connectTimeoutMillis))
            setReadTimeout(Duration.ofMillis(readTimeoutMillis))
        }
        return RestClient.builder().requestFactory(requestFactory)
    }
}
