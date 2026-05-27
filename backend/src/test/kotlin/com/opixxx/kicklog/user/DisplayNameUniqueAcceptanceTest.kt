package com.opixxx.kicklog.user

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
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.patch
import org.springframework.transaction.annotation.Transactional
import java.time.Instant

/**
 * EXEC_PLAN 2026-05-28 p1-display-name-unique — #5 닉네임 unique + 중복 확인 API.
 *
 * 계약:
 * - PATCH /users/me 의 displayName 이 다른 활성 사용자와 충돌 → 409 DISPLAY_NAME_DUPLICATE
 * - 본인 현재 닉네임과 동일 PATCH → 200 (중복 검사 skip / no-op)
 * - 탈퇴자(deletedAt != null) 가 점유했던 닉네임 → 재사용 허용 (UNIQUE INDEX WHERE deleted_at IS NULL)
 * - GET /users/check-display-name?displayName=... 🔒
 *   - 미사용 → 200 + available=true
 *   - 본인 현재 닉네임 → 200 + available=true (false positive 방지)
 *   - 다른 활성 사용자 사용 중 → 200 + available=false
 *   - displayName 파라미터 누락 → 400 VALIDATION_FAILED
 *
 * RED 단계: ErrorCode.DISPLAY_NAME_DUPLICATE 미존재, /users/check-display-name endpoint 미존재,
 * UserStore.findActiveByDisplayName 미존재 → 컴파일 실패 + 신규 시나리오 미통과.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Transactional
class DisplayNameUniqueAcceptanceTest {

    @Autowired
    private lateinit var mockMvc: MockMvc

    @Autowired
    private lateinit var jwtTokenProvider: JwtTokenProvider

    @Autowired
    private lateinit var userStore: UserStore

    @Test
    fun `사용 가능한 닉네임으로 PATCH 하면 200 + 새 displayName 으로 갱신된다`() {
        val me = createUser("홍길동")
        createUser("아무개")  // 다른 활성 사용자, 충돌 없음
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"displayName":"홍길순"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.displayName") { value("홍길순") }
        }
    }

    @Test
    fun `본인 현재 닉네임으로 PATCH 하면 200 (no-op, 중복 검사 skip)`() {
        val me = createUser("홍길동")
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"displayName":"홍길동"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.displayName") { value("홍길동") }
        }
    }

    @Test
    fun `다른 활성 사용자가 사용 중인 닉네임으로 PATCH 하면 409 DISPLAY_NAME_DUPLICATE`() {
        val me = createUser("홍길동")
        createUser("박수비")  // 다른 활성 사용자 점유
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"displayName":"박수비"}"""
        }.andExpect {
            status { isConflict() }
            jsonPath("$.code") { value("DISPLAY_NAME_DUPLICATE") }
        }
    }

    @Test
    fun `탈퇴자 닉네임은 재사용 허용된다 - 200`() {
        // V12 UNIQUE INDEX WHERE deleted_at IS NULL — 탈퇴자 닉네임은 unique 검사 대상 외
        val me = createUser("홍길동")
        createUser("박수비", deleted = true)
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.patch("/users/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"displayName":"박수비"}"""
        }.andExpect {
            status { isOk() }
            jsonPath("$.displayName") { value("박수비") }
        }
    }

    @Test
    fun `미사용 닉네임 가용 확인 - 200 + available=true`() {
        val me = createUser("검사자")
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/check-display-name") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("displayName", "축구왕")
        }.andExpect {
            status { isOk() }
            jsonPath("$.available") { value(true) }
        }
    }

    @Test
    fun `본인 현재 닉네임 가용 확인 - 200 + available=true (false positive 방지)`() {
        val me = createUser("홍길동")
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/check-display-name") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("displayName", "홍길동")
        }.andExpect {
            status { isOk() }
            jsonPath("$.available") { value(true) }
        }
    }

    @Test
    fun `다른 활성 사용자가 사용 중인 닉네임 가용 확인 - 200 + available=false`() {
        val me = createUser("검사자")
        createUser("박수비")
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/check-display-name") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("displayName", "박수비")
        }.andExpect {
            status { isOk() }
            jsonPath("$.available") { value(false) }
        }
    }

    @Test
    fun `탈퇴자 닉네임 가용 확인 - 200 + available=true (재사용 허용)`() {
        val me = createUser("검사자")
        createUser("탈퇴자닉", deleted = true)
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/check-display-name") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("displayName", "탈퇴자닉")
        }.andExpect {
            status { isOk() }
            jsonPath("$.available") { value(true) }
        }
    }

    @Test
    fun `displayName 파라미터 누락이면 400 VALIDATION_FAILED`() {
        val me = createUser("검사자")
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/check-display-name") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    @Test
    fun `displayName 이 공백뿐이면 400 VALIDATION_FAILED`() {
        val me = createUser("검사자")
        val accessToken = jwtTokenProvider.createAccessToken(me.id)

        mockMvc.get("/users/check-display-name") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("displayName", "   ")
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    private fun createUser(displayName: String, deleted: Boolean = false): User {
        val user = User.create(displayName = displayName, email = null)
        val saved = userStore.save(user)
        if (deleted) {
            saved.deletedAt = Instant.now()
            userStore.save(saved)
        }
        return saved
    }
}
