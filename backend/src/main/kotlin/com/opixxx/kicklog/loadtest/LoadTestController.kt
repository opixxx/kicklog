package com.opixxx.kicklog.loadtest

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.common.security.JwtTokenProvider
import jakarta.validation.Valid
import org.springframework.context.annotation.Profile
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

/**
 * 부하 테스트 전용 엔드포인트 — `loadtest` profile 에서만 빈이 등록되므로 운영(prod)에는 아예 존재하지 않는다.
 *
 * - `/loadtest/ping`  : 경로 B(nginx ↔ backend keep-alive lifecycle) 재현용 경량 200 응답 (DB·Kakao 미접촉)
 * - `/loadtest/token` : OAuth 소셜 로그인을 흉내 낼 수 없는 k6 가 보호 엔드포인트를 호출하도록 JWT 우회 발급
 * - `/loadtest/seed`  : 인덱스·집계 병목이 드러나도록 현실 규모 데이터를 대량 시드
 * - `/loadtest/ext`   : 시나리오 1(동시성 처리 모델) 용 **외부 의존 지연** 주입 — DB 미접촉
 * - `/loadtest/db`    : 같은 시나리오의 **DB 커넥션 점유** 주입 — 외부 의존 미접촉
 *
 * 보안: 인증 우회·대량 시드는 **`@Profile("loadtest & !prod")` 격리**가 유일·핵심 안전장치다.
 * prod 프로파일에서는 이 빈이 등록되지 않아 라우트 매핑 자체가 없다(404).
 * `& !prod` 는 운영자가 실수로 `prod,loadtest` 를 동시 활성화해도 운영에 노출되지 않게 하는 추가 방어다.
 */
@RestController
@Profile("loadtest & !prod")
class LoadTestController(
    private val jwtTokenProvider: JwtTokenProvider,
    private val loadTestSeedService: LoadTestSeedService,
    private val upstreamClient: LoadTestUpstreamClient,
    private val dbLoadService: LoadTestDbLoadService,
    private val properties: LoadTestProperties,
) {

    @GetMapping("/loadtest/ping")
    fun ping(): String = "pong"

    @GetMapping("/loadtest/token")
    fun token(@RequestParam userId: Long): LoadTestTokenResponse =
        LoadTestTokenResponse(accessToken = jwtTokenProvider.createAccessToken(userId))

    @PostMapping("/loadtest/seed")
    fun seed(@Valid @RequestBody request: LoadTestSeedRequest): LoadTestSeedResponse =
        LoadTestSeedResponse.from(loadTestSeedService.seed(request.toCommand()))

    /**
     * W-EXT 워크로드 — 외부 HTTP 1회를 **동기 블로킹**으로 호출하고 끝난다. DB 를 건드리지 않는다.
     *
     * DB 를 배제하는 것이 핵심이다. 외부 호출과 DB 를 한 요청에 섞으면 포화한 자원이
     * Tomcat 스레드인지 HikariCP 커넥션인지 귀속할 수 없다 (W-DB·W-MIX 와 분리 측정하는 이유).
     * `/loadtest` 하위 경로는 [LoadTestSecurityConfig] 전용 체인이 permitAll 로 처리하므로
     * JWT 필터·탈퇴 가드(DB 조회)도 타지 않는다.
     */
    @GetMapping("/loadtest/ext")
    fun external(@RequestParam(required = false) delayMs: Int?): LoadTestExternalResponse {
        val delay = resolveDelay(delayMs, properties.defaultDelayMs)

        val startedAt = System.nanoTime()
        val echo = upstreamClient.fetchWithDelay(delay)
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000

        return LoadTestExternalResponse(
            upstreamDelayMs = echo.delayedMs,
            upstreamPid = echo.pid,
            elapsedMs = elapsedMs,
        )
    }

    /**
     * W-DB-POOL 워크로드 — DB 커넥션을 [delayMs] 만큼 점유한다. 외부 의존을 건드리지 않는다.
     *
     * W-EXT 와 짝을 이룬다. 한쪽은 Tomcat 스레드를, 다른 쪽은 HikariCP 커넥션을 구속 자원으로
     * 만들어 **같은 기술(가상 스레드)이 어느 쪽에서 듣고 어느 쪽에서 안 듣는지**를 가른다.
     * 두 워크로드를 섞으면 포화한 자원을 귀속할 수 없으므로 반드시 따로 측정한다.
     */
    @GetMapping("/loadtest/db")
    fun dbLoad(@RequestParam(required = false) delayMs: Int?): LoadTestDbResponse {
        val delay = resolveDelay(delayMs, properties.dbDefaultDelayMs)
        return LoadTestDbResponse(
            requestedDelayMs = delay,
            elapsedMs = dbLoadService.holdConnection(delay),
        )
    }

    // 상한을 두는 이유는 측정 사고 방지다 — 실수로 큰 값을 주면 커넥션·스레드가 그만큼 묶인다.
    private fun resolveDelay(requested: Int?, default: Int): Int {
        val delay = requested ?: default
        if (delay < 0 || delay > properties.maxDelayMs) {
            throw KickLogException(
                ErrorCode.VALIDATION_FAILED,
                "delayMs 는 0~${properties.maxDelayMs} 범위여야 합니다 (요청값: $delay)",
            )
        }
        return delay
    }
}
