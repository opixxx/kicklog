package com.opixxx.kicklog.common

import com.opixxx.kicklog.common.security.JwtTokenProvider
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put

/**
 * EXEC_PLAN 2026-06-10 audit-fixes — (3-A) 인수 시나리오를 MockMvc 인수 테스트로 변환.
 *
 * - 시즌 통계 집계가 쿼터 데이터를 포함해 정확히 집계 (P1 fetch join 회귀)
 * - 경기 목록 커서 페이지네이션 + quarterCount 정합 (P1 2단계 로딩 회귀)
 * - 에러 응답에 8자 hex traceId 포함 (P2-2 신규 — 현재는 traceId 필드 부재로 RED)
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AuditFixesAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Test
    fun `시즌 통계 조회가 쿼터 데이터를 포함해 정확히 집계된다`() {
        // 2026년 경기 3건, 각 쿼터 2개, 매치 거리 1000m → totalDistanceM 합계 3000, quarterCount 6
        val token = jwtTokenProvider.createAccessToken(userId = 7101L)
        val venueId = createVenue(token, "시즌집계운동장")
        saveMatch(token, "cccccccc-cccc-cccc-cccc-ccccccccccc1", venueId, "2026-02-01T09:00:00Z", quarterCount = 2)
        saveMatch(token, "cccccccc-cccc-cccc-cccc-ccccccccccc2", venueId, "2026-03-01T09:00:00Z", quarterCount = 2)
        saveMatch(token, "cccccccc-cccc-cccc-cccc-ccccccccccc3", venueId, "2026-04-01T09:00:00Z", quarterCount = 2)

        mockMvc.get("/users/me/seasons/2026") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isOk() }
            jsonPath("$.matchCount") { value(3) }
            jsonPath("$.quarterCount") { value(6) }
            jsonPath("$.totalDistanceM") { value(3000) }
        }
    }

    @Test
    fun `경기 목록 커서 페이지네이션 후에도 각 item 의 quarterCount 가 정확하다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 7102L)
        val venueId = createVenue(token, "커서quarter운동장")
        saveMatch(token, "dddddddd-dddd-dddd-dddd-ddddddddddd1", venueId, "2026-05-21T09:00:00Z", quarterCount = 1)
        saveMatch(token, "dddddddd-dddd-dddd-dddd-ddddddddddd2", venueId, "2026-05-22T09:00:00Z", quarterCount = 3)

        val firstPage = mockMvc.get("/matches") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
            param("size", "1")
        }.andExpect {
            status { isOk() }
            jsonPath("$.content.length()") { value(1) }
            jsonPath("$.content[0].quarterCount") { value(3) }
            jsonPath("$.hasNext") { value(true) }
            jsonPath("$.nextCursor") { isNotEmpty() }
        }.andReturn().response.contentAsString

        val nextCursor = Regex(""""nextCursor":"([^"]+)"""").find(firstPage)!!.groupValues[1]

        mockMvc.get("/matches") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
            param("size", "1")
            param("cursor", nextCursor)
        }.andExpect {
            status { isOk() }
            jsonPath("$.content.length()") { value(1) }
            jsonPath("$.content[0].quarterCount") { value(1) }
            jsonPath("$.hasNext") { value(false) }
            jsonPath("$.nextCursor") { value(null) }
        }
    }

    @Test
    fun `경기 0건 사용자의 목록은 빈 목록과 null nextCursor 를 반환한다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 7103L)

        mockMvc.get("/matches") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isOk() }
            jsonPath("$.content.length()") { value(0) }
            jsonPath("$.hasNext") { value(false) }
            jsonPath("$.nextCursor") { value(null) }
        }
    }

    @Test
    fun `존재하지 않는 리소스 404 에러 응답에 8자 hex traceId 가 포함된다`() {
        val token = jwtTokenProvider.createAccessToken(userId = 7104L)

        mockMvc.get("/matches/99999999") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isNotFound() }
            jsonPath("$.code") { value("MATCH_NOT_FOUND") }
            jsonPath("$.traceId") { value(org.hamcrest.Matchers.matchesPattern("^[0-9a-f]{8}$")) }
        }
    }

    private fun createVenue(accessToken: String, name: String): Long {
        val response = mockMvc.post("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """
                {
                  "name": "$name",
                  "geoLat": 37.668100,
                  "geoLng": 126.799200,
                  "provider": "kakao",
                  "providerPlaceId": "$name"
                }
            """.trimIndent()
        }.andReturn().response.contentAsString

        return Regex(""""id":(\d+)""").find(response)!!.groupValues[1].toLong()
    }

    private fun saveMatch(
        accessToken: String,
        clientMatchId: String,
        venueId: Long,
        playedAt: String,
        quarterCount: Int,
    ) {
        mockMvc.put("/matches/$clientMatchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = matchJson(venueId, playedAt, quarterCount)
        }.andExpect {
            status { isCreated() }
        }
    }

    private fun matchJson(venueId: Long, playedAt: String, quarterCount: Int): String {
        val quarters = (1..quarterCount).joinToString(",") { n ->
            """
            {
              "quarterNumber": $n,
              "healthKitWorkoutId": "hk-$venueId-$playedAt-$n",
              "startedAt": "$playedAt",
              "endedAt": "$playedAt",
              "durationSeconds": 900,
              "distanceM": ${1000 / quarterCount}
            }
            """.trimIndent()
        }
        return """
            {
              "venueId": $venueId,
              "playedAt": "$playedAt",
              "opponent": "OO FC",
              "position": "MF",
              "goals": 0,
              "assists": 0,
              "teamGoals": 1,
              "opponentGoals": 0,
              "totalDistanceM": 1000,
              "quarters": [$quarters]
            }
        """.trimIndent()
    }
}
