package com.opixxx.kicklog.venue.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.match.repository.InMemoryMatchRepository
import com.opixxx.kicklog.venue.repository.InMemoryVenueRepository
import java.math.BigDecimal
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class VenueServiceTest {

    private val venueRepository = InMemoryVenueRepository()
    private val matchRepository = InMemoryMatchRepository()
    private val service = VenueService(venueRepository, matchRepository)

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

    @Test
    fun `본인 운동장 이름을 수정한다`() {
        val venue = service.createVenue(1L, sampleCommand())

        val updated = service.updateVenue(1L, venue.id, "  풍경 실내구장  ")

        assertEquals("풍경 실내구장", updated.name)
    }

    @Test
    fun `운동장 이름 수정 시 같은 사용자 내 중복 이름은 거부한다`() {
        service.createVenue(1L, sampleCommand(name = "풍경운동장", providerPlaceId = "place-1"))
        val target = service.createVenue(1L, sampleCommand(name = "마포구장", providerPlaceId = "place-2"))

        val exception = assertFailsWith<KickLogException> {
            service.updateVenue(1L, target.id, "풍경운동장")
        }

        assertEquals(ErrorCode.VENUE_NAME_DUPLICATE, exception.errorCode)
    }

    @Test
    fun `다른 사용자 운동장 수정은 거부한다`() {
        val venue = service.createVenue(1L, sampleCommand())

        val exception = assertFailsWith<KickLogException> {
            service.updateVenue(2L, venue.id, "남의 구장")
        }

        assertEquals(ErrorCode.VENUE_NOT_OWNED, exception.errorCode)
    }

    @Test
    fun `없는 운동장 수정은 실패한다`() {
        val exception = assertFailsWith<KickLogException> {
            service.updateVenue(1L, 999L, "없는 구장")
        }

        assertEquals(ErrorCode.VENUE_NOT_FOUND, exception.errorCode)
    }

    @Test
    fun `본인 운동장을 삭제한다`() {
        val venue = service.createVenue(1L, sampleCommand())

        service.deleteVenue(1L, venue.id)

        val exception = assertFailsWith<KickLogException> {
            service.getVenue(1L, venue.id)
        }
        assertEquals(ErrorCode.VENUE_NOT_FOUND, exception.errorCode)
    }

    @Test
    fun `다른 사용자 운동장 삭제는 거부한다`() {
        val venue = service.createVenue(1L, sampleCommand())

        val exception = assertFailsWith<KickLogException> {
            service.deleteVenue(2L, venue.id)
        }

        assertEquals(ErrorCode.VENUE_NOT_OWNED, exception.errorCode)
    }

    @Test
    fun `없는 운동장 삭제는 실패한다`() {
        val exception = assertFailsWith<KickLogException> {
            service.deleteVenue(1L, 999L)
        }

        assertEquals(ErrorCode.VENUE_NOT_FOUND, exception.errorCode)
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
