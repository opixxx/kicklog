package com.opixxx.kicklog.loadtest

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
) {

    @GetMapping("/loadtest/ping")
    fun ping(): String = "pong"

    @GetMapping("/loadtest/token")
    fun token(@RequestParam userId: Long): LoadTestTokenResponse =
        LoadTestTokenResponse(accessToken = jwtTokenProvider.createAccessToken(userId))

    @PostMapping("/loadtest/seed")
    fun seed(@Valid @RequestBody request: LoadTestSeedRequest): LoadTestSeedResponse =
        LoadTestSeedResponse.from(loadTestSeedService.seed(request.toCommand()))
}
