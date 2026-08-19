package com.opixxx.kicklog.common.config

import com.opixxx.kicklog.user.dto.UserResponse
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import tools.jackson.databind.ObjectMapper
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/**
 * EXEC_PLAN 2026-08-19 instant-seconds-serialization — 응답 시간 포맷 계약 고정.
 *
 * 계약 (`docs/spec/api-spec.md` §시간, `docs/architecture/api-conventions.md`):
 * - 모든 `Instant` 응답은 소수부 없는 초 단위 ISO-8601 UTC (`"2026-05-21T10:00:00Z"`).
 *
 * RED 단계: Jackson 3 기본 직렬화는 나노초가 0 이 아니면 `2026-08-19T09:38:29.392099Z` 처럼
 * 소수부를 붙여 계약을 위반한다. 이 때문에 iOS 18 (Darwin/24.6.0) 의 `.iso8601` 디코더가
 * 응답을 파싱하지 못해 신규 사용자의 카카오·애플 로그인이 전부 실패했다.
 */
@SpringBootTest
@ActiveProfiles("test")
class InstantSerializationContractTest {

    @Autowired
    private lateinit var objectMapper: ObjectMapper

    @Test
    fun `나노초가 있는 Instant 도 소수부 없는 초 단위로 직렬화된다`() {
        // given: 장애 당시 실제 로그인 시각 + 마이크로초
        val instantWithNanos = Instant.parse("2026-08-19T09:38:29Z").plusNanos(392_099_000)

        // when
        val json = objectMapper.writeValueAsString(mapOf("createdAt" to instantWithNanos))

        // then
        assertEquals("""{"createdAt":"2026-08-19T09:38:29Z"}""", json)
        assertFalse(json.contains('.'), "응답 시간에 소수부가 포함되면 iOS 18 파서가 거부한다 — 실제값=$json")
    }

    @Test
    fun `나노초가 0 인 Instant 는 기존과 동일한 포맷을 유지한다`() {
        val instantWithoutNanos = Instant.parse("2026-08-19T09:38:29Z")

        val json = objectMapper.writeValueAsString(mapOf("createdAt" to instantWithoutNanos))

        assertEquals("""{"createdAt":"2026-08-19T09:38:29Z"}""", json)
    }

    @Test
    fun `UserResponse 의 createdAt 이 계약 포맷으로 직렬화된다`() {
        val response = UserResponse(
            id = 1L,
            displayName = "김조축",
            email = "abc@example.com",
            createdAt = Instant.parse("2026-01-02T03:00:00Z").plusNanos(123_456_789),
        )

        val json = objectMapper.writeValueAsString(response)

        assertEquals(
            """{"id":1,"displayName":"김조축","email":"abc@example.com","createdAt":"2026-01-02T03:00:00Z"}""",
            json,
        )
    }

    @Test
    fun `나노초는 반올림이 아니라 버림으로 잘린다`() {
        // 999999999ns 를 반올림하면 09:38:30Z 이 되어 실제보다 미래 시각이 된다.
        val maxNanos = Instant.parse("2026-08-19T09:38:29Z").plusNanos(999_999_999)

        val json = objectMapper.writeValueAsString(mapOf("createdAt" to maxNanos))

        assertEquals("""{"createdAt":"2026-08-19T09:38:29Z"}""", json)
    }

    @Test
    fun `epoch 경계값도 계약 포맷을 따른다`() {
        val json = objectMapper.writeValueAsString(mapOf("createdAt" to Instant.EPOCH))

        assertEquals("""{"createdAt":"1970-01-01T00:00:00Z"}""", json)
    }

    @Test
    fun `소수부가 포함된 요청 JSON 은 여전히 역직렬화된다`() {
        // 이미 배포된 iOS 클라이언트가 소수부 포함 값을 보낼 수 있으므로 입력은 관대하게 유지한다.
        val json = """{"createdAt":"2026-08-19T09:38:29.392099Z"}"""

        val parsed = objectMapper.readValue(json, Map::class.java)["createdAt"]
        val instant = objectMapper.convertValue(parsed, Instant::class.java)

        assertEquals(Instant.parse("2026-08-19T09:38:29.392099Z"), instant)
    }
}
