package com.opixxx.kicklog.auth.service

import com.fasterxml.jackson.annotation.JsonProperty
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.http.HttpHeaders
import org.springframework.stereotype.Component
import org.springframework.web.client.HttpClientErrorException
import org.springframework.web.client.RestClient
import org.springframework.web.client.RestClientException

@ConfigurationProperties(prefix = "kicklog.kakao")
data class KakaoProperties(
    val userInfoUrl: String,
)

data class KakaoUserInfoResponse(
    val id: Long,
    @JsonProperty("kakao_account")
    val kakaoAccount: KakaoAccount? = null,
)

data class KakaoAccount(
    val email: String? = null,
    val profile: KakaoProfile? = null,
)

data class KakaoProfile(
    val nickname: String? = null,
)

@Component
@EnableConfigurationProperties(KakaoProperties::class)
class KakaoOAuthClient(
    private val properties: KakaoProperties,
) {
    private val restClient = RestClient.create()

    fun fetchUserInfo(kakaoAccessToken: String): OAuthUserInfo {
        val response = try {
            restClient.get()
                .uri(properties.userInfoUrl)
                .header(HttpHeaders.AUTHORIZATION, "Bearer $kakaoAccessToken")
                .retrieve()
                .body(KakaoUserInfoResponse::class.java)
        } catch (exception: HttpClientErrorException) {
            throw KickLogException(ErrorCode.AUTH_INVALID_KAKAO_TOKEN, cause = exception)
        } catch (exception: RestClientException) {
            throw KickLogException(ErrorCode.EXTERNAL_KAKAO_UNAVAILABLE, cause = exception)
        } ?: throw KickLogException(ErrorCode.EXTERNAL_KAKAO_UNAVAILABLE)

        return OAuthUserInfo(
            providerUserId = response.id.toString(),
            email = response.kakaoAccount?.email,
            displayName = response.kakaoAccount?.profile?.nickname,
        )
    }
}
