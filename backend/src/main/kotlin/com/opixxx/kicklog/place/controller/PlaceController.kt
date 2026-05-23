package com.opixxx.kicklog.place.controller

import com.opixxx.kicklog.place.dto.PlaceSearchResponse
import com.opixxx.kicklog.place.service.PlaceService
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.math.BigDecimal

@RestController
@RequestMapping("/places")
class PlaceController(
    private val placeService: PlaceService,
) {
    @GetMapping("/search")
    fun search(
        @RequestParam("q") query: String,
        @RequestParam(required = false) lat: BigDecimal?,
        @RequestParam(required = false) lng: BigDecimal?,
        @RequestParam(required = false) radius: Int?,
    ): PlaceSearchResponse {
        return PlaceSearchResponse.from(placeService.search(query, lat, lng, radius).places)
    }
}
