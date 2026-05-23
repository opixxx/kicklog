package com.opixxx.kicklog.venue.controller

import com.opixxx.kicklog.common.security.KickLogPrincipal
import com.opixxx.kicklog.venue.dto.CreateVenueRequest
import com.opixxx.kicklog.venue.dto.VenueListResponse
import com.opixxx.kicklog.venue.dto.VenueResponse
import com.opixxx.kicklog.venue.service.VenueService
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/venues")
class VenueController(
    private val venueService: VenueService,
) {
    @PostMapping
    fun create(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @Valid @RequestBody request: CreateVenueRequest,
    ): ResponseEntity<VenueResponse> {
        val existing = venueService.findExistingByProvider(principal.userId, request.toCommand())
        if (existing != null) {
            return ResponseEntity.ok(VenueResponse.from(existing))
        }

        val venue = venueService.createVenue(principal.userId, request.toCommand())
        return ResponseEntity.status(HttpStatus.CREATED).body(VenueResponse.from(venue))
    }

    @GetMapping
    fun list(@AuthenticationPrincipal principal: KickLogPrincipal): VenueListResponse {
        return VenueListResponse(venueService.listVenues(principal.userId).map(VenueResponse::from))
    }

    @GetMapping("/{venueId}")
    fun get(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable venueId: Long,
    ): VenueResponse {
        return VenueResponse.from(venueService.getVenue(principal.userId, venueId))
    }
}
