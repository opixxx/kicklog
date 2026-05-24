package com.opixxx.kicklog.venue.dto

import com.opixxx.kicklog.venue.entity.Venue
import com.opixxx.kicklog.venue.service.CreateVenueCommand
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Size
import java.math.BigDecimal
import java.time.Instant

data class CreateVenueRequest(
    @field:NotBlank(message = "운동장 이름은 필수입니다")
    @field:Size(max = 100, message = "운동장 이름은 100자를 넘을 수 없습니다")
    val name: String,

    @field:NotNull(message = "위도는 필수입니다")
    val geoLat: BigDecimal,

    @field:NotNull(message = "경도는 필수입니다")
    val geoLng: BigDecimal,

    val address: String? = null,
    val roadAddress: String? = null,
    val provider: String? = null,
    val providerPlaceId: String? = null,
) {
    fun toCommand(): CreateVenueCommand {
        return CreateVenueCommand(
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

data class UpdateVenueRequest(
    @field:NotBlank(message = "운동장 이름은 필수입니다")
    @field:Size(max = 100, message = "운동장 이름은 100자를 넘을 수 없습니다")
    val name: String,
)

data class VenueListResponse(
    val venues: List<VenueResponse>,
)

data class VenueResponse(
    val id: Long,
    val name: String,
    val geoLat: BigDecimal,
    val geoLng: BigDecimal,
    val address: String?,
    val roadAddress: String?,
    val provider: String?,
    val providerPlaceId: String?,
    val createdAt: Instant,
) {
    companion object {
        fun from(venue: Venue): VenueResponse {
            return VenueResponse(
                id = venue.id,
                name = venue.name,
                geoLat = venue.geoLat,
                geoLng = venue.geoLng,
                address = venue.address,
                roadAddress = venue.roadAddress,
                provider = venue.provider,
                providerPlaceId = venue.providerPlaceId,
                createdAt = venue.createdAt,
            )
        }
    }
}
