package com.opixxx.kicklog.venue.repository

import com.opixxx.kicklog.venue.entity.Venue
import org.springframework.stereotype.Repository

@Repository
class JpaVenueStore(
    private val venueRepository: VenueRepository,
) : VenueStore {
    override fun save(venue: Venue): Venue = venueRepository.save(venue)

    override fun findById(id: Long): Venue? = venueRepository.findById(id).orElse(null)

    override fun findAllByUserId(userId: Long): List<Venue> = venueRepository.findAllByUserId(userId)

    override fun findByUserIdAndName(userId: Long, name: String): Venue? = venueRepository.findByUserIdAndName(userId, name)

    override fun findByUserIdAndProviderAndProviderPlaceId(
        userId: Long,
        provider: String,
        providerPlaceId: String,
    ): Venue? {
        return venueRepository.findByUserIdAndProviderAndProviderPlaceId(userId, provider, providerPlaceId)
    }
}
