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
        "timestamp" to Instant.now().toString(),
    )
}
