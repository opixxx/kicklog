package com.opixxx.kicklog.auth.service

import com.fasterxml.jackson.annotation.JsonProperty
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatusCode
import org.springframework.stereotype.Component
import org.springframework.web.client.RestClient
import org.springframework.web.client.RestClientException

data class KakaoUserInfo(
    val id: String,
    val email: String?,
    val nickname: String?,
)

interface KakaoOAuthGateway {
    fun fetchUserInfo(kakaoAccessToken: String): KakaoUserInfo
}

@Component
class KakaoOAuthClient : KakaoOAuthGateway {
    private val restClient = RestClient.builder()
        .baseUrl("https://kapi.kakao.com")
        .build()

    override fun fetchUserInfo(kakaoAccessToken: String): KakaoUserInfo {
        try {
            val response = requestUserMe(kakaoAccessToken)
            return response.toUserInfo()
        } catch (exception: AuthException) {
            throw exception
        } catch (exception: RestClientException) {
            throw ExternalKakaoException("카카오 API 호출에 실패했습니다")
        }
    }

    private fun requestUserMe(kakaoAccessToken: String): KakaoUserMeResponse =
        restClient.get()
            .uri("/v2/user/me")
            .header(HttpHeaders.AUTHORIZATION, "Bearer $kakaoAccessToken")
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError) { _, _ -> throw InvalidKakaoTokenException() }
            .onStatus(HttpStatusCode::is5xxServerError) { _, _ -> throw ExternalKakaoException() }
            .body(KakaoUserMeResponse::class.java)
            ?: throw ExternalKakaoException("카카오 사용자 정보 응답이 비어 있습니다")
}

data class KakaoUserMeResponse(
    val id: Long,
    @JsonProperty("kakao_account")
    val kakaoAccount: KakaoAccountResponse? = null,
) {
    fun toUserInfo(): KakaoUserInfo =
        KakaoUserInfo(
            id = id.toString(),
            email = kakaoAccount?.email,
            nickname = kakaoAccount?.profile?.nickname,
        )
}

data class KakaoAccountResponse(
    val email: String? = null,
    val profile: KakaoProfileResponse? = null,
)

data class KakaoProfileResponse(
    val nickname: String? = null,
)
