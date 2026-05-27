package com.opixxx.kicklog.user

import com.opixxx.kicklog.auth.entity.OAuthProvider
import com.opixxx.kicklog.auth.service.AuthService
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
import org.springframework.transaction.annotation.Transactional
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.patch
import org.springframework.test.web.servlet.post

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Transactional
class UserProfileAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var userStore: UserStore

    @Autowired
    private lateinit var authService: AuthService

    @Test
    fun `로그인 사용자는 displayName 만 부분 수정한다`() {
        val user = createUser(displayName = "김조축")
        val accessToken = jwtTokenProvider.createAccessToken(user.id)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"displayName":"김캡틴"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.id") { value(user.id) }
            jsonPath("$.displayName") { value("김캡틴") }
            // hideHeartRate 폐기 (p0-cleanup): 응답에서 키 자체가 사라져야 한다.
            jsonPath("$.hideHeartRate") { doesNotExist() }
        }
    }

    @Test
    fun `PATCH 응답에 hideHeartRate 필드가 더 이상 노출되지 않는다`() {
        // EXEC_PLAN 2026-05-28 p0-cleanup — UserResponse 에서 hideHeartRate 필드 제거.
        val user = createUser(displayName = "필드폐기")
        val accessToken = jwtTokenProvider.createAccessToken(user.id)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"displayName":"필드폐기2"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.displayName") { value("필드폐기2") }
            jsonPath("$.hideHeartRate") { doesNotExist() }
        }
    }

    @Test
    fun `옛 클라이언트가 hideHeartRate 필드를 보내도 200 + displayName 만 반영한다`() {
        // 옛 iOS 빌드 호환 — UpdateMeRequest 가 hideHeartRate 키를 알 수 없어도 ignoreUnknown 으로 통과.
        val user = createUser(displayName = "옛클라")
        val accessToken = jwtTokenProvider.createAccessToken(user.id)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"displayName":"옛클라2","hideHeartRate":true}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.displayName") { value("옛클라2") }
            jsonPath("$.hideHeartRate") { doesNotExist() }
        }
    }

    @Test
    fun `PATCH 요청에 displayName 이 누락되면 400 VALIDATION_FAILED 를 반환한다`() {
        // p0-cleanup — UpdateMeRequest 가 displayName 단일 @NotBlank 필수 필드로 변경됨.
        val user = createUser()
        val accessToken = jwtTokenProvider.createAccessToken(user.id)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = "{}"
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    @Test
    fun `displayName 이 51자면 400 VALIDATION_FAILED 를 반환한다`() {
        val user = createUser()
        val accessToken = jwtTokenProvider.createAccessToken(user.id)
        val tooLong = "가".repeat(51)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"displayName":"$tooLong"}"""
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    @Test
    fun `DELETE 요청은 사용자를 소프트 삭제하고 활성 refresh token 을 모두 폐기한다`() {
        // 사용자 + refresh token 2개를 발급하기 위해 signIn 을 두 번 호출(같은 OAuth identity)한다.
        val first = authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "delete-target",
            email = null,
            displayNameHint = "삭제대상",
        )
        // 같은 사용자에게 두 번째 refresh token 발급
        authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "delete-target",
            email = null,
            displayNameHint = "삭제대상",
        )
        val accessToken = jwtTokenProvider.createAccessToken(first.user.id)

        mockMvc.delete("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isNoContent() }
        }

        val deletedUser = userStore.findById(first.user.id)!!
        assert(deletedUser.isDeleted()) { "soft delete 후 deletedAt 이 설정되어야 합니다" }
    }

    @Test
    fun `삭제 대기 사용자는 cancel-deletion 으로 복구된다`() {
        val user = createUser(displayName = "복구하자", deleted = true)
        val accessToken = jwtTokenProvider.createAccessToken(user.id)

        mockMvc.post("/users/me/cancel-deletion") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isOk() }
            jsonPath("$.id") { value(user.id) }
            jsonPath("$.displayName") { value("복구하자") }
        }

        val restored = userStore.findById(user.id)!!
        assert(!restored.isDeleted()) { "복구 후 deletedAt 은 null 이어야 합니다" }
    }

    @Test
    fun `삭제 대기가 아닌 사용자가 cancel-deletion 호출 시 409 USER_NOT_DELETING`() {
        val user = createUser()
        val accessToken = jwtTokenProvider.createAccessToken(user.id)

        mockMvc.post("/users/me/cancel-deletion") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isConflict() }
            jsonPath("$.code") { value("USER_NOT_DELETING") }
        }
    }

    @Test
    fun `삭제 대기 사용자가 일반 보호 endpoint 호출 시 410 USER_DELETED 로 차단된다`() {
        val user = createUser(displayName = "삭제됨", deleted = true)
        val accessToken = jwtTokenProvider.createAccessToken(user.id)

        mockMvc.get("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isGone() }
            jsonPath("$.code") { value("USER_DELETED") }
        }
    }

    @Test
    fun `display_name 부분 일치로 본인 제외 검색 결과를 반환한다`() {
        val me = createUser(displayName = "수비왕")
        createUser(displayName = "박수비")
        createUser(displayName = "박공격")
        createUser(displayName = "이수비")
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/search") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("q", "수비")
        }.andExpect {
            status { isOk() }
            // 본인(수비왕) 제외, 박수비/이수비 두 명만
            jsonPath("$.users.length()") { value(2) }
            // 응답에 email 필드가 노출되지 않아야 한다
            jsonPath("$.users[0].email") { doesNotExist() }
        }
    }

    @Test
    fun `검색 limit 이 50 을 초과하면 50 으로 clamp 된다`() {
        val me = createUser(displayName = "검색자")
        repeat(60) { index ->
            createUser(displayName = "수비${index + 1}")
        }
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/search") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("q", "수비")
            param("limit", "100")
        }.andExpect {
            status { isOk() }
            jsonPath("$.users.length()") { value(50) }
        }
    }

    @Test
    fun `삭제 대기 사용자는 검색 결과에서 제외된다`() {
        val me = createUser(displayName = "검색자")
        createUser(displayName = "박수비")
        createUser(displayName = "이수비", deleted = true)
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/search") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("q", "수비")
        }.andExpect {
            status { isOk() }
            jsonPath("$.users.length()") { value(1) }
            jsonPath("$.users[0].displayName") { value("박수비") }
        }
    }

    @Test
    fun `q 파라미터가 누락되면 400 VALIDATION_FAILED 를 반환한다`() {
        val me = createUser()
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/search") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    private fun createUser(displayName: String = "테스터", deleted: Boolean = false): User {
        val user = User.create(displayName = displayName, email = null)
        val saved = userStore.save(user)
        if (deleted) {
            saved.deletedAt = java.time.Instant.now()
            userStore.save(saved)
        }
        return saved
    }
}
