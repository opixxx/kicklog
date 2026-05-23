package com.opixxx.kicklog.venue.repository

import com.opixxx.kicklog.venue.entity.Venue

interface VenueStore {
    fun save(venue: Venue): Venue
    fun findById(id: Long): Venue?
    fun findAllByUserId(userId: Long): List<Venue>
    fun findByUserIdAndName(userId: Long, name: String): Venue?
    fun findByUserIdAndProviderAndProviderPlaceId(userId: Long, provider: String, providerPlaceId: String): Venue?
}
