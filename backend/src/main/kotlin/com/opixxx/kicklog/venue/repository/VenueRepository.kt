package com.opixxx.kicklog.venue.repository

import com.opixxx.kicklog.venue.entity.Venue
import org.springframework.data.jpa.repository.JpaRepository

interface VenueRepository : JpaRepository<Venue, Long> {
    fun findAllByUserId(userId: Long): List<Venue>
    fun findByUserIdAndName(userId: Long, name: String): Venue?
    fun findByUserIdAndProviderAndProviderPlaceId(userId: Long, provider: String, providerPlaceId: String): Venue?
}
