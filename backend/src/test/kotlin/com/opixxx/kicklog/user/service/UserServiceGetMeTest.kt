package com.opixxx.kicklog.user.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import java.time.Clock
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/**
 * EXEC_PLAN 2026-06-10 audit-fixes P3 — UserController.me() → UserService.getMe(userId) 위임.
 *
 * 컨트롤러의 인라인 조회/삭제 검증 로직을 서비스로 옮긴다 (requireActiveUser 재사용).
 * getMe 는 활성 사용자면 UserResponse 를 반환하고, 삭제된 사용자면 USER_DELETED 를 던진다.
 */
@SpringBootTest
@ActiveProfiles("test")
class UserServiceGetMeTest {

    @Autowired
    private lateinit var userService: UserService

    @Autowired
    private lateinit var userRepository: UserRepository

    @Autowired
    private lateinit var clock: Clock

    @Test
    fun `활성 사용자는 본인 프로필 UserResponse 를 반환한다`() {
        val user = userRepository.save(User.create(displayName = "프로필조회자", email = "me@example.com"))

        val response = userService.getMe(user.id)

        assertEquals(user.id, response.id)
        assertEquals("프로필조회자", response.displayName)
        assertEquals("me@example.com", response.email)
    }

    @Test
    fun `삭제된 사용자는 USER_DELETED 로 거부한다`() {
        val user = userRepository.save(User.create(displayName = "삭제된프로필", email = null))
        user.markDeleted(now = Instant.now(clock))
        userRepository.save(user)

        val exception = assertFailsWith<KickLogException> {
            userService.getMe(user.id)
        }
        assertEquals(ErrorCode.USER_DELETED, exception.errorCode)
    }

    @Test
    fun `존재하지 않는 사용자는 USER_NOT_FOUND 로 거부한다`() {
        val exception = assertFailsWith<KickLogException> {
            userService.getMe(999_999L)
        }
        assertEquals(ErrorCode.USER_NOT_FOUND, exception.errorCode)
    }
}
