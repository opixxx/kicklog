package com.opixxx.kicklog.place.service

import java.math.BigDecimal

fun interface KakaoLocalClient {
    fun searchKeyword(
        query: String,
        lat: BigDecimal?,
        lng: BigDecimal?,
        radius: Int,
    ): List<Place>
}
