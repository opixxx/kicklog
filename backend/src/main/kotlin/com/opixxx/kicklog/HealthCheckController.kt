package com.opixxx.kicklog

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController
import java.time.Instant

@RestController
class HealthCheckController {

    @GetMapping("/")
    fun root(): Map<String, Any> = mapOf(
        "service" to "kicklog-backend",
        "status" to "ok",
        // toString() 으로 미리 문자열화하면 JacksonConfig 의 초 단위 직렬화를 우회한다 — Instant 그대로 넘긴다.
        "timestamp" to Instant.now(),
    )
}
