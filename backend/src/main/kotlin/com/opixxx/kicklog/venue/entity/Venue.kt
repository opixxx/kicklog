package com.opixxx.kicklog.venue.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.math.BigDecimal
import java.time.Instant

@Entity
@Table(name = "venues")
class Venue(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long = 0,

    @Column(name = "user_id", nullable = false)
    var userId: Long,

    @Column(name = "name", nullable = false, length = 100)
    var name: String,

    @Column(name = "geo_lat", nullable = false, precision = 9, scale = 6)
    var geoLat: BigDecimal,

    @Column(name = "geo_lng", nullable = false, precision = 9, scale = 6)
    var geoLng: BigDecimal,

    @Column(name = "address")
    var address: String? = null,

    @Column(name = "road_address")
    var roadAddress: String? = null,

    @Column(name = "provider", length = 20)
    var provider: String? = null,

    @Column(name = "provider_place_id")
    var providerPlaceId: String? = null,

    @Column(name = "created_at", nullable = false)
    var createdAt: Instant = Instant.now(),
) {
    companion object {
        fun create(
            userId: Long,
            name: String,
            geoLat: BigDecimal,
            geoLng: BigDecimal,
            address: String?,
            roadAddress: String?,
            provider: String?,
            providerPlaceId: String?,
        ): Venue {
            return Venue(
                userId = userId,
                name = name,
                geoLat = geoLat,
                geoLng = geoLng,
                address = address,
                roadAddress = roadAddress,
                provider = provider,
                providerPlaceId = providerPlaceId,
            )
        }
    }
}
