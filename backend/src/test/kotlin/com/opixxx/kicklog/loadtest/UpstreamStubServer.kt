package com.opixxx.kicklog.loadtest

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * W-EXT 테스트용 mock 외부 의존 — JDK 내장 [HttpServer] 로 **실제 HTTP** 를 받는다.
 *
 * MockRestServiceServer 를 쓰지 않는 이유: 그쪽은 RestClient 의 request factory 를 테스트용으로
 * 갈아끼운다. 그러면 "어떤 ClientHttpRequestFactory 가 주입됐는지"와 "커넥션이 실제로 어떻게
 * 동작하는지"를 검증할 수 없게 되는데, 그 두 가지가 바로 이 하네스의 측정 대상이다.
 * 따라서 프로덕션 코드가 고른 팩토리로 진짜 소켓 통신을 하게 두고, 상대편만 stub 으로 세운다.
 *
 * 포트는 0 으로 바인딩해 OS 가 비어 있는 포트를 고르게 한다(테스트 병렬 실행 충돌 방지).
 */
class UpstreamStubServer private constructor(private val server: HttpServer) {

    /** true 로 두면 `/delay` 가 500 을 반환한다 — upstream 장애 케이스 재현용. */
    @Volatile
    var failWithServerError: Boolean = false

    private val received = AtomicInteger(0)

    val port: Int get() = server.address.port

    val baseUrl: String get() = "http://localhost:$port"

    /** stub 이 실제로 받은 요청 수 — "검증 실패 시 외부 호출을 하지 않는다"를 증명하는 데 쓴다. */
    val receivedRequestCount: Int get() = received.get()

    fun resetRequestCount() {
        received.set(0)
    }

    fun stop() {
        server.stop(0)
    }

    private fun handleDelay(exchange: HttpExchange) {
        received.incrementAndGet()
        try {
            if (failWithServerError) {
                // 장애 응답 본문에 내부 정보를 일부러 담는다 — 백엔드가 이걸 그대로 클라이언트에
                // 흘리지 않는지(스택·내부 URL 미노출) 확인하기 위한 미끼다.
                respond(
                    exchange,
                    status = 500,
                    body = """{"error":"upstream boom","internalUrl":"$baseUrl/delay"}""",
                )
                return
            }

            val delayMs = queryParamMs(exchange.requestURI.query)
            if (delayMs > 0) {
                Thread.sleep(delayMs.toLong())
            }
            respond(exchange, status = 200, body = """{"delayedMs":$delayMs,"pid":$STUB_PID}""")
        } finally {
            exchange.close()
        }
    }

    private fun respond(exchange: HttpExchange, status: Int, body: String) {
        val bytes = body.toByteArray(StandardCharsets.UTF_8)
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(status, bytes.size.toLong())
        exchange.responseBody.write(bytes)
    }

    private fun queryParamMs(query: String?): Int =
        query
            ?.split("&")
            ?.map { it.split("=", limit = 2) }
            ?.firstOrNull { it.size == 2 && it[0] == "ms" }
            ?.get(1)
            ?.toIntOrNull()
            ?: 0

    companion object {
        /** stub 이 돌려주는 가짜 pid — 응답이 정말 stub 에서 왔는지 식별하는 표식. */
        const val STUB_PID: Int = 4242

        fun start(): UpstreamStubServer {
            val server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
            // 기본 executor 는 단일 스레드 직렬 처리라 동시 요청이 큐에 쌓인다.
            // 지연 주입 stub 이 스스로 병목이 되면 측정·검증 대상이 바뀌므로 작은 풀을 둔다.
            server.executor = Executors.newFixedThreadPool(8)
            val stub = UpstreamStubServer(server)
            server.createContext("/delay", stub::handleDelay)
            server.start()
            return stub
        }

        /**
         * 아무도 듣고 있지 않은 로컬 포트를 하나 고른다 — upstream 미기동(connection refused) 재현용.
         * 바인딩했다가 즉시 닫으므로, 재사용될 확률이 사실상 없는 포트 번호를 얻는다.
         */
        fun pickClosedPort(): Int =
            java.net.ServerSocket(0).use { it.localPort }
    }
}
