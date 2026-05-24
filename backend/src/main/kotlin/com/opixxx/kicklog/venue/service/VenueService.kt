package com.opixxx.kicklog.venue.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.match.repository.MatchStore
import com.opixxx.kicklog.venue.entity.Venue
import com.opixxx.kicklog.venue.repository.VenueStore
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.math.RoundingMode

data class CreateVenueCommand(
    val name: String,
    val geoLat: BigDecimal,
    val geoLng: BigDecimal,
    val address: String?,
    val roadAddress: String?,
    val provider: String?,
    val providerPlaceId: String?,
)

@Service
class VenueService(
    private val venueRepository: VenueStore,
    private val matchRepository: MatchStore,
) {
    @Transactional(readOnly = true)
    fun findExistingByProvider(userId: Long, command: CreateVenueCommand): Venue? {
        val provider = command.provider?.trim()?.lowercase()?.takeIf { it.isNotBlank() }
        val providerPlaceId = command.providerPlaceId?.trim()?.takeIf { it.isNotBlank() }
        if (provider == null || providerPlaceId == null) return null
        return venueRepository.findByUserIdAndProviderAndProviderPlaceId(userId, provider, providerPlaceId)
    }

    @Transactional
    fun createVenue(userId: Long, command: CreateVenueCommand): Venue {
        val normalizedName = command.name.trim()
        val normalizedProvider = command.provider?.trim()?.lowercase()?.takeIf { it.isNotBlank() }
        val normalizedProviderPlaceId = command.providerPlaceId?.trim()?.takeIf { it.isNotBlank() }

        if (normalizedProvider != null && normalizedProviderPlaceId != null) {
            val existing = venueRepository.findByUserIdAndProviderAndProviderPlaceId(
                userId,
                normalizedProvider,
                normalizedProviderPlaceId,
            )
            if (existing != null) return existing
        }

        if (venueRepository.findByUserIdAndName(userId, normalizedName) != null) {
            throw KickLogException(ErrorCode.VENUE_NAME_DUPLICATE)
        }

        return venueRepository.save(
            Venue.create(
                userId = userId,
                name = normalizedName,
                geoLat = command.geoLat.setScale(6, RoundingMode.HALF_UP),
                geoLng = command.geoLng.setScale(6, RoundingMode.HALF_UP),
                address = command.address?.trim()?.takeIf { it.isNotBlank() },
                roadAddress = command.roadAddress?.trim()?.takeIf { it.isNotBlank() },
                provider = normalizedProvider,
                providerPlaceId = normalizedProviderPlaceId,
            ),
        )
    }

    @Transactional(readOnly = true)
    fun listVenues(userId: Long): List<Venue> = venueRepository.findAllByUserId(userId)

    @Transactional(readOnly = true)
    fun getVenue(userId: Long, venueId: Long): Venue {
        return findOwnedVenue(userId, venueId)
    }

    @Transactional
    fun updateVenue(userId: Long, venueId: Long, name: String): Venue {
        val venue = findOwnedVenue(userId, venueId)
        val normalizedName = name.trim()
        val duplicated = venueRepository.findByUserIdAndName(userId, normalizedName)
        if (duplicated != null && duplicated.id != venue.id) {
            throw KickLogException(ErrorCode.VENUE_NAME_DUPLICATE)
        }
        venue.name = normalizedName
        return venueRepository.save(venue)
    }

    @Transactional
    fun deleteVenue(userId: Long, venueId: Long) {
        val venue = findOwnedVenue(userId, venueId)
        matchRepository.clearVenueId(venue.id)
        venueRepository.delete(venue)
    }

    private fun findOwnedVenue(userId: Long, venueId: Long): Venue {
        val venue = venueRepository.findById(venueId)
            ?: throw KickLogException(ErrorCode.VENUE_NOT_FOUND)
        if (venue.userId != userId) {
            throw KickLogException(ErrorCode.VENUE_NOT_OWNED)
        }
        return venue
    }
}
