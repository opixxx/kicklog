package com.opixxx.kicklog.place.dto

import com.opixxx.kicklog.place.service.Place
import java.math.BigDecimal

data class PlaceSearchResponse(
    val places: List<PlaceResponse>,
) {
    companion object {
        fun from(places: List<Place>): PlaceSearchResponse {
            return PlaceSearchResponse(places.map(PlaceResponse::from))
        }
    }
}

data class PlaceResponse(
    val provider: String,
    val providerPlaceId: String,
    val name: String,
    val address: String,
    val roadAddress: String?,
    val lat: BigDecimal,
    val lng: BigDecimal,
    val distanceM: Int?,
) {
    companion object {
        fun from(place: Place): PlaceResponse {
            return PlaceResponse(
                provider = place.provider,
                providerPlaceId = place.providerPlaceId,
                name = place.name,
                address = place.address,
                roadAddress = place.roadAddress,
                lat = place.lat,
                lng = place.lng,
                distanceM = place.distanceM,
            )
        }
    }
}
