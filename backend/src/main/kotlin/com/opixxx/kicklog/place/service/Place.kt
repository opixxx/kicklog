package com.opixxx.kicklog.place.service

import java.math.BigDecimal

data class Place(
    val provider: String,
    val providerPlaceId: String,
    val name: String,
    val address: String,
    val roadAddress: String?,
    val lat: BigDecimal,
    val lng: BigDecimal,
    val distanceM: Int?,
)
