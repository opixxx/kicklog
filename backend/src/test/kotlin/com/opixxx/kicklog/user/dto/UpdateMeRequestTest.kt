package com.opixxx.kicklog.user.dto

import jakarta.validation.Validation
import jakarta.validation.Validator
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * EXEC_PLAN 2026-05-28 p0-cleanup — UpdateMeRequest 정책 변경.
 *
 * 변경 후 계약:
 * - hideHeartRate 필드 제거
 * - displayName 만 받는 단일 필드 DTO
 * - displayName 은 `@NotBlank` 필수 → 빈 본문은 명확히 400 VALIDATION_FAILED
 *
 * RED 단계: 현재 DTO 는 displayName/hideHeartRate 둘 다 nullable + `@AssertTrue hasAtLeastOneField`
 * 구조라 컴파일 / 단언 결과가 새 정책과 어긋난다.
 */
class UpdateMeRequestTest {

    private lateinit var validator: Validator

    @BeforeTest
    fun setUp() {
        validator = Validation.buildDefaultValidatorFactory().validator
    }

    @Test
    fun `displayName 만으로 생성된 요청은 검증을 통과한다`() {
        val request = UpdateMeRequest(displayName = "김캡틴")

        val violations = validator.validate(request)

        assertEquals(0, violations.size, "violations: ${violations.map { it.message }}")
    }

    @Test
    fun `displayName 이 null 이면 NotBlank 검증에 실패한다`() {
        // 새 정책: displayName 은 단일 필드 + @NotBlank 필수.
        val request = UpdateMeRequest(displayName = null)

        val violations = validator.validate(request)

        assertTrue(
            violations.any { it.propertyPath.toString() == "displayName" },
            "displayName NotBlank 검증 누락 — 현재 violations: ${violations.map { "${it.propertyPath}:${it.message}" }}",
        )
    }

    @Test
    fun `displayName 이 빈 문자열이면 NotBlank 검증에 실패한다`() {
        val request = UpdateMeRequest(displayName = "")

        val violations = validator.validate(request)

        assertTrue(
            violations.any { it.propertyPath.toString() == "displayName" },
            "displayName 빈 문자열 violation 누락 — 현재 violations: ${violations.map { "${it.propertyPath}:${it.message}" }}",
        )
    }

    @Test
    fun `displayName 이 51 자면 Size 검증에 실패한다`() {
        val request = UpdateMeRequest(displayName = "가".repeat(51))

        val violations = validator.validate(request)

        assertTrue(
            violations.any { it.propertyPath.toString() == "displayName" },
            "displayName Size(max=50) violation 누락 — 현재 violations: ${violations.map { "${it.propertyPath}:${it.message}" }}",
        )
    }
}
