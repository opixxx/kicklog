package com.opixxx.kicklog.place.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import org.springframework.stereotype.Service
import java.math.BigDecimal

@Service
class PlaceService(
    private val kakaoLocalClient: KakaoLocalClient,
) {
    fun search(
        query: String,
        lat: BigDecimal?,
        lng: BigDecimal?,
        radius: Int?,
    ): PlaceSearchResult {
        val normalizedQuery = query.trim()
        if (normalizedQuery.isBlank()) {
            throw KickLogException(ErrorCode.VALIDATION_FAILED, "검색어는 필수입니다")
        }

        val normalizedRadius = (radius ?: DEFAULT_RADIUS).coerceIn(MIN_RADIUS, MAX_RADIUS)
        val hasBothCoordinates = lat != null && lng != null
        val places = kakaoLocalClient.searchKeyword(
            query = normalizedQuery,
            lat = lat.takeIf { hasBothCoordinates },
            lng = lng.takeIf { hasBothCoordinates },
            radius = normalizedRadius,
        )
        return PlaceSearchResult(places)
    }

    companion object {
        private const val MIN_RADIUS = 1
        private const val DEFAULT_RADIUS = 5_000
        private const val MAX_RADIUS = 20_000
    }
}

data class PlaceSearchResult(
    val places: List<Place>,
)
