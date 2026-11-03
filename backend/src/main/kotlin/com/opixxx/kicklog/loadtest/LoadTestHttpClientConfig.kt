package com.opixxx.kicklog.loadtest

import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.context.annotation.Profile
import org.springframework.http.client.ClientHttpRequestFactory
import org.springframework.http.client.JdkClientHttpRequestFactory
import org.springframework.http.client.SimpleClientHttpRequestFactory
import org.springframework.web.client.RestClient
import java.net.http.HttpClient
import java.time.Duration

/**
 * W-EXT 워크로드용 RestClient — request factory 를 property 로 교체할 수 있다.
 *
 * **왜 교체 가능해야 하는가**: 운영 인증 경로는 커넥션 풀이 없는 형상이다. 그 형상 그대로의
 * 천장과, 풀을 붙인 뒤의 천장을 **같은 바이너리에서** 비교해야 차이를 커넥션 관리에 귀속할 수 있다.
 * 기본값을 SIMPLE 로 두는 이유도 같다 — 기준선이 운영 형상이어야 측정이 운영을 대변한다.
 *
 * 운영 `config/RestClientConfig` 는 건드리지 않는다. 개선안의 운영 적용은 측정 후 별도 판단이다.
 */
@Configuration
@Profile("loadtest & !prod")
@EnableConfigurationProperties(LoadTestProperties::class)
class LoadTestHttpClientConfig {

    @Bean
    fun loadTestUpstreamRestClient(properties: LoadTestProperties): RestClient =
        RestClient.builder()
            .baseUrl(properties.upstreamBaseUrl)
            .requestFactory(requestFactory(properties))
            .build()

    private fun requestFactory(properties: LoadTestProperties): ClientHttpRequestFactory =
        when (properties.httpClient) {
            LoadTestProperties.HttpClientKind.SIMPLE -> SimpleClientHttpRequestFactory().apply {
                setConnectTimeout(Duration.ofMillis(properties.connectTimeoutMillis))
                setReadTimeout(Duration.ofMillis(properties.readTimeoutMillis))
            }

            // HTTP/1.1 로 고정한다. JDK HttpClient 기본값은 HTTP/2 협상이라,
            // 두 형상의 차이에 프로토콜 차이가 섞이면 커넥션 풀 효과를 분리할 수 없다.
            LoadTestProperties.HttpClientKind.POOLED -> JdkClientHttpRequestFactory(
                HttpClient.newBuilder()
                    .version(HttpClient.Version.HTTP_1_1)
                    .connectTimeout(Duration.ofMillis(properties.connectTimeoutMillis))
                    .build(),
            ).apply {
                setReadTimeout(Duration.ofMillis(properties.readTimeoutMillis))
            }
        }
}
