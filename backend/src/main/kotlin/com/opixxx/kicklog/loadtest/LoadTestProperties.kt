package com.opixxx.kicklog.loadtest

import org.springframework.boot.context.properties.ConfigurationProperties

/**
 * 시나리오 1(외부 의존 지연 하의 동시성 처리 모델) 측정 노브 — `kicklog.loadtest.*`.
 *
 * 전부 **이미지 재빌드 없이 env 로 교체**할 수 있어야 한다. 측정은 "같은 바이너리에서
 * 설정만 바꿔 비교"하는 것이 전제다 — 바이너리가 다르면 차이를 설정에 귀속할 수 없다.
 */
@ConfigurationProperties(prefix = "kicklog.loadtest")
data class LoadTestProperties(
    /** mock 외부 의존 base URL (`tools/loadtest/mock-upstream.mjs`). */
    val upstreamBaseUrl: String = "http://localhost:9100",

    /** 외부 호출에 쓸 HTTP 클라이언트 형상. 기본값은 **운영 인증 경로와 동일한** SIMPLE 이다. */
    val httpClient: HttpClientKind = HttpClientKind.SIMPLE,

    // 커넥션 풀 상한 노브는 두지 않는다. `java.net.http.HttpClient` 는 풀 크기를 빌더로 받지 않고
    // JVM 전역 시스템 프로퍼티(`jdk.httpclient.connectionPoolSize`)로만 받는다.
    // property 로 선언해 두면 "바꿨다고 기록했는데 실제로는 안 바뀐" 측정이 된다 — 가장 찾기 어려운
    // 종류의 오류다. 필요해지면 기동 플래그(`-Djdk.httpclient.connectionPoolSize=N`)로 주고 그 사실을 기록할 것.

    val connectTimeoutMillis: Long = 2_000,

    /**
     * read timeout. 주입 지연(기본 200ms)보다 충분히 커야 한다.
     * 과부하 구간에서 upstream 큐 대기까지 포함되므로 지연의 수십 배로 둔다 —
     * 여기서 끊기면 "스레드 포화" 대신 "타임아웃"이 측정돼 원인이 바뀐다.
     */
    val readTimeoutMillis: Long = 10_000,

    /** `delayMs` 파라미터 미지정 시 기본 주입 지연 (외부 의존). */
    val defaultDelayMs: Int = 200,

    /**
     * DB 커넥션 점유 지연의 기본값.
     * 풀 10 기준 천장이 `10 ÷ 0.05` = 200 rps 가 되도록 잡았다 — 호스트가 여유인 구간에서
     * 풀이 구속 자원이 되게 하는 값이다.
     */
    val dbDefaultDelayMs: Int = 50,

    /** 측정 사고 방지 상한 — 이 값을 넘는 `delayMs` 는 400 으로 거부한다. */
    val maxDelayMs: Int = 10_000,
) {
    /**
     * - [SIMPLE] : `SimpleClientHttpRequestFactory` (HttpURLConnection).
     *   **운영 인증 경로(`config/RestClientConfig`)와 같은 형상**이라 "현재 구조의 천장"을 재는 기준선이다.
     *   HttpURLConnection 의 keep-alive 캐시는 호스트당 기본 5(`http.maxConnections`)로 작아,
     *   동시 호출이 그보다 많으면 매번 새 커넥션을 열고 닫는다.
     * - [POOLED] : `JdkClientHttpRequestFactory` (`java.net.http.HttpClient`) — 커넥션 풀 보유.
     */
    enum class HttpClientKind { SIMPLE, POOLED }
}
