package com.opixxx.kicklog.common.config

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import tools.jackson.core.JsonGenerator
import tools.jackson.databind.JacksonModule
import tools.jackson.databind.SerializationContext
import tools.jackson.databind.module.SimpleModule
import tools.jackson.databind.ser.std.StdSerializer
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * 응답 JSON 의 시간 표현을 API 계약에 고정한다.
 *
 * 계약: 모든 `Instant` 는 소수부 없는 초 단위 ISO-8601 UTC (`"2026-05-21T10:00:00Z"`)
 * — `docs/spec/api-spec.md` §시간, `docs/architecture/api-conventions.md`.
 *
 * Jackson 기본 동작은 나노초가 0 이면 소수부를 생략하고 0 이 아니면 붙이는 **비결정적 출력**이라,
 * 같은 엔드포인트가 값에 따라 다른 포맷을 내보낸다. iOS 18 의 `JSONDecoder.iso8601` 디코더는
 * 소수부를 거부하므로 이 비결정성이 신규 로그인 실패로 이어졌다 (2026-08-19 장애).
 *
 * 역직렬화(요청)는 관대하게 둔다 — 이미 배포된 클라이언트가 소수부 포함 값을 보낼 수 있다.
 */
@Configuration
class JacksonConfig {

    @Bean
    fun secondsPrecisionInstantModule(): JacksonModule =
        SimpleModule("SecondsPrecisionInstantModule")
            .addSerializer(Instant::class.java, SecondsPrecisionInstantSerializer())
}

/** `Instant` 를 초 단위로 버림(truncate)해 소수부 없는 ISO-8601 UTC 문자열로 쓴다. */
private class SecondsPrecisionInstantSerializer : StdSerializer<Instant>(Instant::class.java) {

    override fun serialize(value: Instant, gen: JsonGenerator, ctxt: SerializationContext) {
        // 반올림하면 실제보다 미래 시각이 되므로 반드시 버림이어야 한다.
        gen.writeString(DateTimeFormatter.ISO_INSTANT.format(value.truncatedTo(ChronoUnit.SECONDS)))
    }
}
