package com.opixxx.kicklog.user.entity

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * EXEC_PLAN 2026-05-28 p1-display-name-unique — User.create 의 displayName 정규화.
 *
 * 계약:
 * - displayName 앞뒤 공백은 trim 후 저장 ("  홍길동  " → "홍길동")
 * - trim 결과가 빈 문자열이면 기본 "사용자" 로 대체 (기존 정책 유지)
 *
 * RED 단계: 현재 `User.create` 는 `takeIf { it.isNotBlank() } ?: "사용자"` 만 적용하므로 trim 미반영.
 */
class UserCreateTest {

    @Test
    fun `displayName 앞뒤 공백은 trim 적용된다`() {
        val user = User.create(displayName = "  홍길동  ", email = null)

        assertEquals("홍길동", user.displayName)
    }

    @Test
    fun `trim 결과가 빈 문자열이면 기본 사용자 로 대체된다`() {
        val user = User.create(displayName = "   ", email = null)

        assertEquals("사용자", user.displayName)
    }

    @Test
    fun `정상 입력은 그대로 저장된다`() {
        val user = User.create(displayName = "홍길동", email = null)

        assertEquals("홍길동", user.displayName)
    }
}
