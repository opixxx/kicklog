package com.opixxx.kicklog.place.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import org.junit.jupiter.api.Test
import org.springframework.http.HttpMethod
import org.springframework.http.MediaType
import org.springframework.test.web.client.ExpectedCount
import org.springframework.test.web.client.MockRestServiceServer
import org.springframework.test.web.client.match.MockRestRequestMatchers.header
import org.springframework.test.web.client.match.MockRestRequestMatchers.method
import org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo
import org.springframework.test.web.client.response.MockRestResponseCreators.withBadGateway
import org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess
import org.springframework.web.client.RestClient
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class KakaoLocalRestClientTest {

    private val restClientBuilder = RestClient.builder()
    private val server = MockRestServiceServer.bindTo(restClientBuilder).build()
    private val client = KakaoLocalRestClient(
        properties = KakaoLocalProperties(
            restApiKey = "test-rest-key",
            localSearchUrl = "https://dapi.kakao.com/v2/local/search/keyword.json",
        ),
        restClientBuilder = restClientBuilder,
    )

    @Test
    fun `카카오 장소 검색 응답을 KickLog DTO로 변환한다`() {
        server.expect(ExpectedCount.once(), requestTo("https://dapi.kakao.com/v2/local/search/keyword.json?query=%ED%92%8D%EA%B2%BD%EC%9A%B4%EB%8F%99%EC%9E%A5&size=15&x=126.79&y=37.66&radius=5000"))
            .andExpect(method(HttpMethod.GET))
            .andExpect(header("Authorization", "KakaoAK test-rest-key"))
            .andRespond(
                withSuccess(
                    """
                    {
                      "documents": [
                        {
                          "id": "12345",
                          "place_name": "풍경운동장",
                          "address_name": "경기 고양시 일산동구 풍동",
                          "road_address_name": "경기 고양시 일산동구 숲속마을로",
                          "y": "37.6681",
                          "x": "126.7992",
                          "distance": "320"
                        }
                      ]
                    }
                    """.trimIndent(),
                    MediaType.APPLICATION_JSON,
                ),
            )

        val places = client.searchKeyword(
            query = "풍경운동장",
            lat = "37.66".toBigDecimal(),
            lng = "126.79".toBigDecimal(),
            radius = 5_000,
        )

        assertEquals("kakao", places.single().provider)
        assertEquals("12345", places.single().providerPlaceId)
        assertEquals("풍경운동장", places.single().name)
        assertEquals(320, places.single().distanceM)
        server.verify()
    }

    @Test
    fun `카카오 장애는 EXTERNAL_KAKAO_UNAVAILABLE로 변환한다`() {
        server.expect(ExpectedCount.once(), requestTo("https://dapi.kakao.com/v2/local/search/keyword.json?query=%EC%B6%95%EA%B5%AC%EC%9E%A5&size=15&radius=5000"))
            .andRespond(withBadGateway())

        val exception = assertFailsWith<KickLogException> {
            client.searchKeyword(query = "축구장", lat = null, lng = null, radius = 5_000)
        }

        assertEquals(ErrorCode.EXTERNAL_KAKAO_UNAVAILABLE, exception.errorCode)
        server.verify()
    }
}
