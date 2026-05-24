package com.opixxx.kicklog.venue

import com.opixxx.kicklog.common.security.JwtTokenProvider
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.patch
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class VenueAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Test
    fun `로그인 사용자는 운동장을 저장하고 목록에서 조회한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 1L)

        val created = mockMvc.post("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = venueJson()
        }.andExpect {
            status { isCreated() }
            jsonPath("$.id") { isNumber() }
            jsonPath("$.name") { value("풍경운동장") }
            jsonPath("$.provider") { value("kakao") }
            jsonPath("$.providerPlaceId") { value("12345") }
        }.andReturn().response.contentAsString
        val venueId = Regex(""""id":(\d+)""").find(created)!!.groupValues[1].toLong()

        mockMvc.get("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.venues[0].name") { value("풍경운동장") }
        }

        mockMvc.get("/venues/$venueId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.name") { value("풍경운동장") }
        }
    }

    @Test
    fun `같은 카카오 장소를 다시 저장하면 200과 기존 id를 반환한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 10L)

        val first = mockMvc.post("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = venueJson()
        }.andReturn().response.contentAsString

        val firstId = Regex(""""id":(\d+)""").find(first)!!.groupValues[1].toLong()

        mockMvc.post("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = venueJson(name = "풍경운동장 새 이름")
        }.andExpect {
            status { isOk() }
            jsonPath("$.id") { value(firstId) }
            jsonPath("$.name") { value("풍경운동장") }
        }
    }

    @Test
    fun `로그인 사용자는 본인 운동장 이름을 수정한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 20L)
        val venueId = createVenue(accessToken, name = "수정 전 운동장", providerPlaceId = "patch-venue")

        mockMvc.patch("/venues/$venueId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"name":"수정 후 운동장"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.name") { value("수정 후 운동장") }
        }

        mockMvc.get("/venues/$venueId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.name") { value("수정 후 운동장") }
        }
    }

    @Test
    fun `다른 사용자의 운동장 이름 수정은 거부된다`() {
        val ownerToken = jwtTokenProvider.createAccessToken(userId = 21L)
        val otherToken = jwtTokenProvider.createAccessToken(userId = 22L)
        val venueId = createVenue(ownerToken, name = "남의 운동장", providerPlaceId = "patch-other")

        mockMvc.patch("/venues/$venueId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $otherToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"name":"수정 시도"}"""
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("VENUE_NOT_OWNED") }
        }
    }

    @Test
    fun `로그인 사용자는 본인 운동장을 삭제한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 23L)
        val venueId = createVenue(accessToken, name = "삭제 운동장", providerPlaceId = "delete-venue")

        mockMvc.delete("/venues/$venueId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isNoContent() }
        }

        mockMvc.get("/venues/$venueId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isNotFound() }
            jsonPath("$.code") { value("VENUE_NOT_FOUND") }
        }
    }

    @Test
    fun `운동장 삭제 후 기존 경기의 venueId는 null로 조회된다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 24L)
        val venueId = createVenue(accessToken, name = "경기 연결 운동장", providerPlaceId = "delete-match-venue")
        val matchId = saveMatch(accessToken, venueId)

        mockMvc.delete("/venues/$venueId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isNoContent() }
        }

        mockMvc.get("/matches/$matchId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.venueId") { value(null) }
        }
    }

    @Test
    fun `다른 사용자의 운동장 삭제는 거부된다`() {
        val ownerToken = jwtTokenProvider.createAccessToken(userId = 25L)
        val otherToken = jwtTokenProvider.createAccessToken(userId = 26L)
        val venueId = createVenue(ownerToken, name = "삭제 남의 운동장", providerPlaceId = "delete-other")

        mockMvc.delete("/venues/$venueId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $otherToken")
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("VENUE_NOT_OWNED") }
        }
    }

    @Test
    fun `인증 없이 운동장 목록을 조회하면 거부된다`() {
        mockMvc.get("/venues")
            .andExpect {
                status { isUnauthorized() }
            }
    }

    private fun createVenue(accessToken: String, name: String, providerPlaceId: String): Long {
        val response = mockMvc.post("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = venueJson(name = name, providerPlaceId = providerPlaceId)
        }.andReturn().response.contentAsString

        return Regex(""""id":(\d+)""").find(response)!!.groupValues[1].toLong()
    }

    private fun saveMatch(accessToken: String, venueId: Long): Long {
        val response = mockMvc.put("/matches/24242424-2424-2424-2424-242424242424") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """
                {
                  "venueId": $venueId,
                  "playedAt": "2026-05-23T09:00:00Z",
                  "goals": 1,
                  "assists": 0,
                  "quarters": [
                    {
                      "quarterNumber": 1,
                      "healthKitWorkoutId": "hk-delete-venue",
                      "startedAt": "2026-05-23T09:00:00Z",
                      "endedAt": "2026-05-23T09:15:00Z"
                    }
                  ]
                }
            """.trimIndent()
        }.andReturn().response.contentAsString

        return Regex(""""id":(\d+)""").find(response)!!.groupValues[1].toLong()
    }

    private fun venueJson(name: String = "풍경운동장", providerPlaceId: String = "12345"): String {
        return """
            {
              "name": "$name",
              "geoLat": 37.668100,
              "geoLng": 126.799200,
              "address": "경기 고양시 일산동구 풍동",
              "roadAddress": "경기 고양시 일산동구 숲속마을로",
              "provider": "kakao",
              "providerPlaceId": "$providerPlaceId"
            }
        """.trimIndent()
    }
}
