package com.opixxx.kicklog.place.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class PlaceServiceTest {

    private val client = FakeKakaoLocalClient()
    private val service = PlaceService(client)

    @Test
    fun `키워드와 현재 위치로 장소를 검색한다`() {
        client.result = listOf(
            Place(
                provider = "kakao",
                providerPlaceId = "12345",
                name = "풍경운동장",
                address = "경기 고양시 일산동구 풍동",
                roadAddress = "경기 고양시 일산동구 숲속마을로",
                lat = 37.6681.toBigDecimal(),
                lng = 126.7992.toBigDecimal(),
                distanceM = 320,
            ),
        )

        val response = service.search(
            query = "풍경운동장",
            lat = 37.66.toBigDecimal(),
            lng = 126.79.toBigDecimal(),
            radius = null,
        )

        assertEquals("풍경운동장", response.places.single().name)
        assertEquals(5_000, client.lastRadius)
        assertEquals(37.66.toBigDecimal(), client.lastLat)
        assertEquals(126.79.toBigDecimal(), client.lastLng)
    }

    @Test
    fun `radius는 카카오 최대값인 20000으로 제한한다`() {
        service.search(
            query = "축구장",
            lat = null,
            lng = null,
            radius = 30_000,
        )

        assertEquals(20_000, client.lastRadius)
        assertEquals(null, client.lastLat)
        assertEquals(null, client.lastLng)
    }

    @Test
    fun `빈 검색어는 거부한다`() {
        val exception = assertFailsWith<KickLogException> {
            service.search(query = "  ", lat = null, lng = null, radius = null)
        }

        assertEquals(ErrorCode.VALIDATION_FAILED, exception.errorCode)
    }
}

private class FakeKakaoLocalClient : KakaoLocalClient {
    var result: List<Place> = emptyList()
    var lastQuery: String? = null
    var lastLat: java.math.BigDecimal? = null
    var lastLng: java.math.BigDecimal? = null
    var lastRadius: Int? = null

    override fun searchKeyword(
        query: String,
        lat: java.math.BigDecimal?,
        lng: java.math.BigDecimal?,
        radius: Int,
    ): List<Place> {
        lastQuery = query
        lastLat = lat
        lastLng = lng
        lastRadius = radius
        return result
    }
}
