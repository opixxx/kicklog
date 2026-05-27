package com.opixxx.kicklog.friend

import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserStore
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import org.springframework.transaction.annotation.Transactional

/**
 * EXEC_PLAN 2026-05-28 p1-display-name-unique — #4 초대 링크 도메인 폐기 회귀.
 *
 * 계약:
 * - POST/GET/DELETE /invitations 엔드포인트는 모두 제거되어 404 응답
 * - POST /friendships 는 targetUserId 단독으로 동작 — token 필드는 클라가 함께 보내도 무시 (Jackson ignoreUnknown)
 *
 * RED 단계: InvitationController 가 아직 존재하므로 POST /invitations 가 201 응답.
 * GREEN 단계에서 InvitationController + InvitationService + 관련 DTO/Repo 통째 삭제 시 통과한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Transactional
class InvitationEndpointRemovalTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var userStore: UserStore

    @Test
    fun `POST 슬래시 invitations 엔드포인트는 제거되어 404 응답`() {
        val me = createUser("초대제거")
        val token = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.post("/invitations") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isNotFound() }
        }
    }

    @Test
    fun `GET 슬래시 invitations 엔드포인트는 제거되어 404 응답`() {
        val me = createUser("초대조회제거")
        val token = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/invitations") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isNotFound() }
        }
    }

    @Test
    fun `DELETE 슬래시 invitations 슬래시 id 엔드포인트는 제거되어 404 응답`() {
        val me = createUser("초대폐기제거")
        val token = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.delete("/invitations/1") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isNotFound() }
        }
    }

    @Test
    fun `POST 슬래시 friendships 는 targetUserId 와 token 을 같이 보내도 token 은 무시되고 정상 201 응답`() {
        // 옛 iOS 빌드가 token 필드를 함께 보내는 경우에 대한 호환성 — Jackson ignoreUnknown 의존
        val me = createUser("호환요청자")
        val other = createUser("호환수신자")
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.post("/friendships") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"targetUserId":${other.id},"token":"garbage1"}"""
        }.andExpect {
            status { isCreated() }
            jsonPath("$.status") { value("pending") }
            jsonPath("$.initiatedByMe") { value(true) }
        }
    }

    private fun createUser(displayName: String): User {
        return userStore.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }
}
