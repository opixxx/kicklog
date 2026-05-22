package com.opixxx.kicklog.auth

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.opixxx.kicklog.auth.repository.OAuthIdentityRepository
import com.opixxx.kicklog.auth.repository.RefreshTokenRepository
import com.opixxx.kicklog.auth.service.ExternalKakaoException
import com.opixxx.kicklog.auth.service.InvalidKakaoTokenException
import com.opixxx.kicklog.auth.service.KakaoOAuthGateway
import com.opixxx.kicklog.auth.service.KakaoUserInfo
import com.opixxx.kicklog.user.repository.UserRepository
import org.hamcrest.Matchers.blankOrNullString
import org.hamcrest.Matchers.not
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.boot.test.context.TestConfiguration
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Primary
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.post

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class KakaoSignInAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var fakeKakaoOAuthGateway: FakeKakaoOAuthGateway

    @Autowired
    private lateinit var userRepository: UserRepository

    @Autowired
    private lateinit var oauthIdentityRepository: OAuthIdentityRepository

    @Autowired
    private lateinit var refreshTokenRepository: RefreshTokenRepository

    private val objectMapper = ObjectMapper()

    @BeforeEach
    fun setUp() {
        refreshTokenRepository.deleteAll()
        oauthIdentityRepository.deleteAll()
        userRepository.deleteAll()
        fakeKakaoOAuthGateway.reset()
    }

    @Test
    fun `신규 카카오 사용자는 로그인하고 JWT를 발급받는다`() {
        fakeKakaoOAuthGateway.userInfo = KakaoUserInfo(
            id = "12345",
            email = "kakao@example.com",
            nickname = "김조축",
        )

        mockMvc.post("/auth/kakao/signin") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"kakaoAccessToken":"valid-kakao-token"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.accessToken", not(blankOrNullString()))
            jsonPath("$.refreshToken", not(blankOrNullString()))
            jsonPath("$.user.id") { isNumber() }
            jsonPath("$.user.displayName") { value("김조축") }
            jsonPath("$.user.email") { value("kakao@example.com") }
            jsonPath("$.user.hideHeartRate") { value(false) }
        }
    }

    @Test
    fun `같은 카카오 사용자로 다시 로그인하면 사용자를 중복 생성하지 않는다`() {
        fakeKakaoOAuthGateway.userInfo = KakaoUserInfo(
            id = "12345",
            email = "kakao@example.com",
            nickname = "김조축",
        )

        repeat(2) {
            mockMvc.post("/auth/kakao/signin") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"kakaoAccessToken":"valid-kakao-token"}"""
            }.andExpect {
                status { isOk() }
            }
        }

        kotlin.test.assertEquals(1, userRepository.count())
        kotlin.test.assertEquals(1, oauthIdentityRepository.count())
        kotlin.test.assertEquals(2, refreshTokenRepository.count())
    }

    @Test
    fun `유효하지 않은 카카오 토큰은 401을 반환한다`() {
        fakeKakaoOAuthGateway.exception = InvalidKakaoTokenException()

        mockMvc.post("/auth/kakao/signin") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"kakaoAccessToken":"expired-kakao-token"}"""
        }.andExpect {
            status { isUnauthorized() }
            jsonPath("$.code") { value("AUTH_INVALID_KAKAO_TOKEN") }
        }
    }

    @Test
    fun `카카오 장애는 502를 반환한다`() {
        fakeKakaoOAuthGateway.exception = ExternalKakaoException()

        mockMvc.post("/auth/kakao/signin") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"kakaoAccessToken":"valid-kakao-token"}"""
        }.andExpect {
            status { isBadGateway() }
            jsonPath("$.code") { value("EXTERNAL_KAKAO_UNAVAILABLE") }
        }
    }

    @Test
    fun `빈 카카오 토큰은 400을 반환한다`() {
        mockMvc.post("/auth/kakao/signin") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"kakaoAccessToken":""}"""
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
            jsonPath("$.field") { value("kakaoAccessToken") }
        }
    }

    @Test
    fun `refresh token으로 새 access token을 발급받는다`() {
        fakeKakaoOAuthGateway.userInfo = KakaoUserInfo(id = "12345", email = null, nickname = "김조축")
        val signInResponse = mockMvc.post("/auth/kakao/signin") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"kakaoAccessToken":"valid-kakao-token"}"""
        }.andReturn().response.contentAsString.toJson()

        val refreshToken = signInResponse["refreshToken"].asText()

        mockMvc.post("/auth/refresh") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"refreshToken":"$refreshToken"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.accessToken", not(blankOrNullString()))
            jsonPath("$.refreshToken") { value(refreshToken) }
        }
    }

    @Test
    fun `깨진 refresh token은 401을 반환한다`() {
        mockMvc.post("/auth/refresh") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"refreshToken":"broken-token"}"""
        }.andExpect {
            status { isUnauthorized() }
            jsonPath("$.code") { value("AUTH_INVALID_REFRESH") }
        }
    }

    private fun String.toJson(): JsonNode = objectMapper.readTree(this)

    @TestConfiguration
    class KakaoSignInTestConfig {
        @Bean
        @Primary
        fun fakeKakaoOAuthGateway(): FakeKakaoOAuthGateway = FakeKakaoOAuthGateway()
    }
}

class FakeKakaoOAuthGateway : KakaoOAuthGateway {
    var userInfo = KakaoUserInfo(id = "12345", email = null, nickname = "사용자")
    var exception: RuntimeException? = null

    override fun fetchUserInfo(kakaoAccessToken: String): KakaoUserInfo {
        exception?.let { throw it }
        return userInfo
    }

    fun reset() {
        userInfo = KakaoUserInfo(id = "12345", email = null, nickname = "사용자")
        exception = null
    }
}
