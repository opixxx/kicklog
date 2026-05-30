package com.opixxx.kicklog.loadtest

import org.springframework.context.annotation.Profile
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController

/**
 * 부하 테스트 전용 경량 엔드포인트 — 경로 B(nginx ↔ backend keep-alive lifecycle) 재현용.
 *
 * Kakao/DB 를 타지 않는 순수 200 응답으로 nginx ↔ backend hop 만 격리해 측정한다.
 * `loadtest` profile 에서만 빈이 등록되므로 운영(prod)에는 아예 존재하지 않는다.
 */
@RestController
@Profile("loadtest")
class LoadTestController {

    @GetMapping("/loadtest/ping")
    fun ping(): String = "pong"
}
