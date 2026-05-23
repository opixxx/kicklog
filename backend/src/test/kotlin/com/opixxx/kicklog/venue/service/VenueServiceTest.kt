package com.opixxx.kicklog.venue.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.venue.repository.InMemoryVenueRepository
import java.math.BigDecimal
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class VenueServiceTest {

    private val venueRepository = InMemoryVenueRepository()
    private val service = VenueService(venueRepository)

    @Test
    fun `운동장을 저장한다`() {
        val venue = service.createVenue(
            userId = 1L,
            command = CreateVenueCommand(
                name = "풍경운동장",
                geoLat = BigDecimal("37.668100"),
                geoLng = BigDecimal("126.799200"),
                address = "경기 고양시 일산동구 풍동",
                roadAddress = "경기 고양시 일산동구 숲속마을로",
                provider = "kakao",
                providerPlaceId = "12345",
            ),
        )

        assertEquals("풍경운동장", venue.name)
        assertEquals("12345", venue.providerPlaceId)
    }

    @Test
    fun `같은 사용자와 카카오 place id면 기존 운동장을 재사용한다`() {
        val first = service.createVenue(1L, sampleCommand())
        val second = service.createVenue(1L, sampleCommand(name = "풍경운동장 새 이름"))

        assertEquals(first.id, second.id)
        assertEquals(1, venueRepository.count())
    }

    @Test
    fun `같은 사용자 내 이름 중복은 거부한다`() {
        service.createVenue(1L, sampleCommand(provider = null, providerPlaceId = null))

        val exception = assertFailsWith<KickLogException> {
            service.createVenue(1L, sampleCommand(provider = null, providerPlaceId = null))
        }

        assertEquals(ErrorCode.VENUE_NAME_DUPLICATE, exception.errorCode)
    }

    @Test
    fun `다른 사용자 운동장 조회는 거부한다`() {
        val venue = service.createVenue(1L, sampleCommand())

        val exception = assertFailsWith<KickLogException> {
            service.getVenue(userId = 2L, venueId = venue.id)
        }

        assertEquals(ErrorCode.VENUE_NOT_OWNED, exception.errorCode)
    }

    private fun sampleCommand(
        name: String = "풍경운동장",
        provider: String? = "kakao",
        providerPlaceId: String? = "12345",
    ): CreateVenueCommand {
        return CreateVenueCommand(
            name = name,
            geoLat = BigDecimal("37.668100"),
            geoLng = BigDecimal("126.799200"),
            address = "경기 고양시 일산동구 풍동",
            roadAddress = "경기 고양시 일산동구 숲속마을로",
            provider = provider,
            providerPlaceId = providerPlaceId,
        )
    }
}
