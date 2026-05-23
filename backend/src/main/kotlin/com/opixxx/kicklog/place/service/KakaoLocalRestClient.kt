package com.opixxx.kicklog.place.service

import com.fasterxml.jackson.annotation.JsonProperty
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.http.HttpHeaders
import org.springframework.stereotype.Component
import org.springframework.web.client.RestClient
import org.springframework.web.client.RestClientException
import org.springframework.web.util.UriComponentsBuilder
import java.math.BigDecimal

@ConfigurationProperties(prefix = "kicklog.kakao")
data class KakaoLocalProperties(
    val restApiKey: String,
    val localSearchUrl: String,
)

data class KakaoKeywordSearchResponse(
    val documents: List<KakaoPlaceDocument> = emptyList(),
)

data class KakaoPlaceDocument(
    val id: String,
    @JsonProperty("place_name")
    val placeName: String,
    @JsonProperty("address_name")
    val addressName: String,
    @JsonProperty("road_address_name")
    val roadAddressName: String? = null,
    val x: String,
    val y: String,
    val distance: String? = null,
)

@Component
@EnableConfigurationProperties(KakaoLocalProperties::class)
class KakaoLocalRestClient(
    private val properties: KakaoLocalProperties,
    restClientBuilder: RestClient.Builder,
) : KakaoLocalClient {
    private val restClient = restClientBuilder.build()

    override fun searchKeyword(
        query: String,
        lat: BigDecimal?,
        lng: BigDecimal?,
        radius: Int,
    ): List<Place> {
        val uri = UriComponentsBuilder.fromUriString(properties.localSearchUrl)
            .queryParam("query", query)
            .queryParam("size", 15)
            .apply {
                if (lat != null && lng != null) {
                    queryParam("x", lng)
                    queryParam("y", lat)
                }
            }
            .queryParam("radius", radius)
            .build()
            .encode()
            .toUri()

        val response = try {
            restClient.get()
                .uri(uri)
                .header(HttpHeaders.AUTHORIZATION, "KakaoAK ${properties.restApiKey}")
                .retrieve()
                .body(KakaoKeywordSearchResponse::class.java)
        } catch (exception: RestClientException) {
            throw KickLogException(ErrorCode.EXTERNAL_KAKAO_UNAVAILABLE, cause = exception)
        } ?: throw KickLogException(ErrorCode.EXTERNAL_KAKAO_UNAVAILABLE)

        return response.documents.map { it.toPlace() }
    }

    private fun KakaoPlaceDocument.toPlace(): Place {
        return Place(
            provider = "kakao",
            providerPlaceId = id,
            name = placeName,
            address = addressName,
            roadAddress = roadAddressName,
            lat = BigDecimal(y),
            lng = BigDecimal(x),
            distanceM = distance?.takeIf { it.isNotBlank() }?.toIntOrNull(),
        )
    }
}
