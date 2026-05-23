package com.opixxx.kicklog.config

import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.client.SimpleClientHttpRequestFactory
import org.springframework.web.client.RestClient
import java.time.Duration

@Configuration
class RestClientConfig {
    @Bean
    fun restClientBuilder(
        @Value("\${kicklog.kakao.connect-timeout-millis:2000}") connectTimeoutMillis: Long,
        @Value("\${kicklog.kakao.read-timeout-millis:3000}") readTimeoutMillis: Long,
    ): RestClient.Builder {
        val requestFactory = SimpleClientHttpRequestFactory().apply {
            setConnectTimeout(Duration.ofMillis(connectTimeoutMillis))
            setReadTimeout(Duration.ofMillis(readTimeoutMillis))
        }
        return RestClient.builder().requestFactory(requestFactory)
    }
}
