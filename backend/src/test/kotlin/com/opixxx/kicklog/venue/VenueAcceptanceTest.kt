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
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post

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

        mockMvc.post("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = venueJson()
        }.andExpect {
            status { isCreated() }
            jsonPath("$.id") { isNumber() }
            jsonPath("$.name") { value("풍경운동장") }
            jsonPath("$.provider") { value("kakao") }
            jsonPath("$.providerPlaceId") { value("12345") }
        }

        mockMvc.get("/venues") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.venues[0].name") { value("풍경운동장") }
        }

        mockMvc.get("/venues/1") {
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
    fun `인증 없이 운동장 목록을 조회하면 거부된다`() {
        mockMvc.get("/venues")
            .andExpect {
                status { isUnauthorized() }
            }
    }

    private fun venueJson(name: String = "풍경운동장"): String {
        return """
            {
              "name": "$name",
              "geoLat": 37.668100,
              "geoLng": 126.799200,
              "address": "경기 고양시 일산동구 풍동",
              "roadAddress": "경기 고양시 일산동구 숲속마을로",
              "provider": "kakao",
              "providerPlaceId": "12345"
            }
        """.trimIndent()
    }
}
