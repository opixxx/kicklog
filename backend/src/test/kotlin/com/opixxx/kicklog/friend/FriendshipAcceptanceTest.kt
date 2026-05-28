package com.opixxx.kicklog.friend

import com.opixxx.kicklog.common.security.JwtTokenProvider
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
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
import org.springframework.test.web.servlet.patch
import org.springframework.test.web.servlet.post

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class FriendshipAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var userRepository: UserRepository

    @Test
    fun `친구 요청을 보내고 상대가 수락하면 친구 목록에 보인다`() {
        val requester = createUser("친구요청자")
        val recipient = createUser("친구수락자")
        val requesterToken = jwtTokenProvider.createAccessToken(requester.id)
        val recipientToken = jwtTokenProvider.createAccessToken(recipient.id)

        val friendshipId = requestFriend(requesterToken, recipient.id)

        mockMvc.get("/friendships/pending") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $recipientToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.requests[0].friendshipId") { value(friendshipId) }
            jsonPath("$.requests[0].from.id") { value(requester.id) }
        }

        mockMvc.patch("/friendships/$friendshipId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $recipientToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"action":"accept"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.friendshipId") { value(friendshipId) }
            jsonPath("$.status") { value("accepted") }
        }

        mockMvc.get("/friendships") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $requesterToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.friends[0].friendshipId") { value(friendshipId) }
            jsonPath("$.friends[0].user.id") { value(recipient.id) }
            jsonPath("$.friends[0].user.displayName") { value("친구수락자") }
        }
    }

    @Test
    fun `보낸 친구 요청은 본인이 수락할 수 없다`() {
        val requester = createUser("수락불가요청자")
        val recipient = createUser("수락불가상대")
        val requesterToken = jwtTokenProvider.createAccessToken(requester.id)
        val friendshipId = requestFriend(requesterToken, recipient.id)

        mockMvc.patch("/friendships/$friendshipId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $requesterToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"action":"accept"}"""
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("FRIEND_NOT_RECIPIENT") }
        }
    }

    @Test
    fun `친구 요청 입력 값이 올바르지 않으면 거부된다`() {
        val requester = createUser("검증요청자")
        val requesterToken = jwtTokenProvider.createAccessToken(requester.id)

        mockMvc.post("/friendships") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $requesterToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"targetUserId":0}"""
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    @Test
    fun `관계 당사자가 아니면 친구 관계를 삭제할 수 없다`() {
        val requester = createUser("삭제요청자")
        val recipient = createUser("삭제수락자")
        val outsider = createUser("삭제비당사자")
        val requesterToken = jwtTokenProvider.createAccessToken(requester.id)
        val recipientToken = jwtTokenProvider.createAccessToken(recipient.id)
        val outsiderToken = jwtTokenProvider.createAccessToken(outsider.id)
        val friendshipId = requestFriend(requesterToken, recipient.id)

        mockMvc.patch("/friendships/$friendshipId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $recipientToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"action":"accept"}"""
        }.andExpect {
            status { isOk() }
        }

        mockMvc.delete("/friendships/$friendshipId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $outsiderToken")
        }.andExpect {
            status { isForbidden() }
            jsonPath("$.code") { value("FRIEND_NOT_PARTICIPANT") }
        }
    }

    private fun createUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun requestFriend(accessToken: String, targetUserId: Long): Long {
        val response = mockMvc.post("/friendships") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"targetUserId":$targetUserId}"""
        }.andExpect {
            status { isCreated() }
            jsonPath("$.status") { value("pending") }
            jsonPath("$.initiatedByMe") { value(true) }
        }.andReturn().response.contentAsString

        return Regex(""""friendshipId":(\d+)""").find(response)!!.groupValues[1].toLong()
    }
}
