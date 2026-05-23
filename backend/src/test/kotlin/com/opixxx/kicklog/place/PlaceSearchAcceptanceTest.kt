package com.opixxx.kicklog.place

import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.place.service.KakaoLocalClient
import com.opixxx.kicklog.place.service.Place
import org.hamcrest.Matchers.not
import org.hamcrest.Matchers.blankOrNullString
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.boot.test.context.TestConfiguration
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Primary
import org.springframework.http.HttpHeaders
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import java.math.BigDecimal

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class PlaceSearchAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Test
    fun `인증한 사용자는 장소를 검색한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 1L)

        mockMvc.get("/places/search") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("q", "풍경운동장")
            param("lat", "37.66")
            param("lng", "126.79")
        }.andExpect {
            status { isOk() }
            jsonPath("$.places[0].provider") { value("kakao") }
            jsonPath("$.places[0].providerPlaceId", not(blankOrNullString()))
            jsonPath("$.places[0].name") { value("풍경운동장") }
            jsonPath("$.places[0].distanceM") { value(320) }
        }
    }

    @Test
    fun `인증 없이 장소 검색을 요청하면 거부된다`() {
        mockMvc.get("/places/search") {
            param("q", "풍경운동장")
        }.andExpect {
            status { isUnauthorized() }
        }
    }

    @Test
    fun `검색어가 없으면 400을 반환한다`() {
        val accessToken = jwtTokenProvider.createAccessToken(userId = 1L)

        mockMvc.get("/places/search") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    @TestConfiguration
    class PlaceSearchTestConfig {
        @Bean
        @Primary
        fun fakeKakaoLocalClient(): KakaoLocalClient {
            return KakaoLocalClient { _, _, _, _ ->
                listOf(
                    Place(
                        provider = "kakao",
                        providerPlaceId = "12345",
                        name = "풍경운동장",
                        address = "경기 고양시 일산동구 풍동",
                        roadAddress = "경기 고양시 일산동구 숲속마을로",
                        lat = BigDecimal("37.6681"),
                        lng = BigDecimal("126.7992"),
                        distanceM = 320,
                    ),
                )
            }
        }
    }
}
