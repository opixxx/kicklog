package com.opixxx.kicklog.venue.repository

import com.opixxx.kicklog.venue.entity.Venue

class InMemoryVenueRepository : VenueStore {
    private val venues = linkedMapOf<Long, Venue>()
    private var sequence = 1L

    override fun save(venue: Venue): Venue {
        if (venue.id == 0L) {
            venue.id = sequence++
        }
        venues[venue.id] = venue
        return venue
    }

    override fun findById(id: Long): Venue? = venues[id]

    override fun findAllByUserId(userId: Long): List<Venue> {
        return venues.values.filter { it.userId == userId }
    }

    override fun findByUserIdAndName(userId: Long, name: String): Venue? {
        return venues.values.firstOrNull { it.userId == userId && it.name == name }
    }

    override fun findByUserIdAndProviderAndProviderPlaceId(
        userId: Long,
        provider: String,
        providerPlaceId: String,
    ): Venue? {
        return venues.values.firstOrNull {
            it.userId == userId && it.provider == provider && it.providerPlaceId == providerPlaceId
        }
    }

    fun count(): Int = venues.size
}
