package com.opixxx.kicklog.friend

import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.http.HttpHeaders
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class InvitationAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var userRepository: UserRepository

    @Test
    fun `로그인 사용자는 초대 링크를 만들고 비로그인 사용자는 토큰 정보를 조회한다`() {
        val inviter = createUser("초대발신자")
        val token = jwtTokenProvider.createAccessToken(inviter.id)

        val response = mockMvc.post("/invitations") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isCreated() }
            jsonPath("$.id") { exists() }
            jsonPath("$.token") { isNotEmpty() }
            jsonPath("$.url") { isNotEmpty() }
            jsonPath("$.expiresAt") { isNotEmpty() }
            jsonPath("$.useCount") { value(0) }
        }.andReturn().response.contentAsString

        val invitationToken = Regex(""""token":"([^"]+)"""").find(response)!!.groupValues[1]

        mockMvc.get("/invitations/$invitationToken").andExpect {
            status { isOk() }
            jsonPath("$.token") { value(invitationToken) }
            jsonPath("$.inviter.id") { value(inviter.id) }
            jsonPath("$.inviter.displayName") { value("초대발신자") }
            jsonPath("$.valid") { value(true) }
        }
    }

    @Test
    fun `내 활성 초대 링크 목록을 조회한다`() {
        val inviter = createUser("목록발신자")
        val token = jwtTokenProvider.createAccessToken(inviter.id)
        createInvitation(token)
        createInvitation(token)

        mockMvc.get("/invitations") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isOk() }
            jsonPath("$.invitations.length()") { value(2) }
            jsonPath("$.invitations[0].token") { isNotEmpty() }
        }
    }

    @Test
    fun `초대 링크 소유자가 아니면 폐기할 수 없다`() {
        val inviter = createUser("폐기발신자")
        val outsider = createUser("폐기비소유자")
        val inviterToken = jwtTokenProvider.createAccessToken(inviter.id)
        val outsiderToken = jwtTokenProvider.createAccessToken(outsider.id)
        val invitationId = createInvitation(inviterToken).first

        mockMvc.delete("/invitations/$invitationId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $outsiderToken")
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("INVITATION_NOT_OWNED") }
        }
    }

    @Test
    fun `폐기된 초대 링크는 공개 조회할 수 없다`() {
        val inviter = createUser("폐기조회발신자")
        val token = jwtTokenProvider.createAccessToken(inviter.id)
        val (invitationId, invitationToken) = createInvitation(token)

        mockMvc.delete("/invitations/$invitationId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
        }.andExpect {
            status { isNoContent() }
        }

        mockMvc.get("/invitations/$invitationToken").andExpect {
            status { isGone() }
            jsonPath("$.code") { value("INVITATION_REVOKED") }
        }
    }

    private fun createUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun createInvitation(accessToken: String): Pair<Long, String> {
        val response = mockMvc.post("/invitations") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andReturn().response.contentAsString
        val id = Regex(""""id":(\d+)""").find(response)!!.groupValues[1].toLong()
        val token = Regex(""""token":"([^"]+)"""").find(response)!!.groupValues[1]
        return id to token
    }
}
