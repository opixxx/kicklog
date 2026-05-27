package com.opixxx.kicklog.auth

import com.opixxx.kicklog.auth.entity.OAuthProvider
import com.opixxx.kicklog.auth.service.AuthService
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserStore
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import org.springframework.transaction.annotation.Transactional
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * EXEC_PLAN 2026-05-28 p1-display-name-unique — 회원가입 시 닉네임 충돌 자동 suffix.
 *
 * 계약:
 * - displayNameHint 가 이미 활성 사용자가 사용 중이면 가입 흐름은 끊기지 않고 자동으로 "${hint}-${hex4}" 형태로 변경한다.
 * - 충돌 없으면 hint 그대로 사용한다.
 *
 * RED 단계: AuthService.signIn 이 충돌을 처리하지 않아 displayName 이 hint 그대로 저장되어
 * UNIQUE INDEX 위반으로 가입 흐름이 실패하거나, 충돌 검사 자체가 없어 두 사용자가 같은 displayName 으로 공존.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class SignInDisplayNameSuffixAcceptanceTest {

    @Autowired
    private lateinit var authService: AuthService

    @Autowired
    private lateinit var userStore: UserStore

    @Test
    fun `같은 displayName 이 활성 사용자에게 점유돼 있으면 가입 시 자동 suffix 가 붙는다`() {
        // given: "축구왕" 점유 사용자
        userStore.save(User.create(displayName = "축구왕", email = "occupied@example.com"))

        // when: 신규 카카오 사용자가 같은 hint 로 가입 시도
        val response = authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "kakao-new-1",
            email = null,
            displayNameHint = "축구왕",
        )

        // then: 가입 성공 + displayName 이 "축구왕-XXXX" 형태 (X = HEX) 로 자동 변환
        assertTrue(
            Regex("^축구왕-[0-9A-Fa-f]{4}$").matches(response.user.displayName),
            "displayName 자동 suffix 형식 위반 — 실제값=${response.user.displayName}",
        )
    }

    @Test
    fun `displayName 충돌이 없으면 hint 를 그대로 사용한다`() {
        val response = authService.signIn(
            provider = OAuthProvider.KAKAO,
            providerUserId = "kakao-new-2",
            email = null,
            displayNameHint = "축구초보",
        )

        assertEquals("축구초보", response.user.displayName)
    }
}
