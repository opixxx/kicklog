package com.opixxx.kicklog.user.controller

import com.opixxx.kicklog.common.security.KickLogPrincipal
import com.opixxx.kicklog.user.dto.DisplayNameCheckResponse
import com.opixxx.kicklog.user.dto.UpdateMeRequest
import com.opixxx.kicklog.user.dto.UserResponse
import com.opixxx.kicklog.user.dto.UserSearchResponse
import com.opixxx.kicklog.user.service.UserService
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.validation.annotation.Validated
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/users")
@Validated
class UserController(
    private val userService: UserService,
) {
    @GetMapping("/me")
    fun me(@AuthenticationPrincipal principal: KickLogPrincipal): UserResponse {
        return userService.getMe(principal.userId)
    }

    @PatchMapping("/me")
    fun updateMe(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @Valid @RequestBody request: UpdateMeRequest,
    ): UserResponse {
        // displayName 은 `@NotBlank` 통과 시점에 non-null 보장.
        return userService.updateMe(
            userId = principal.userId,
            displayName = request.displayName!!,
        )
    }

    @DeleteMapping("/me")
    fun deleteMe(@AuthenticationPrincipal principal: KickLogPrincipal): ResponseEntity<Void> {
        userService.softDelete(principal.userId)
        return ResponseEntity.noContent().build()
    }

    @PostMapping("/me/cancel-deletion")
    fun cancelDeletion(@AuthenticationPrincipal principal: KickLogPrincipal): UserResponse {
        return userService.cancelDeletion(principal.userId)
    }

    @GetMapping("/search")
    fun search(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @RequestParam("q")
        @NotBlank(message = "q 파라미터는 필수입니다")
        @Size(min = 1, max = 50, message = "q 는 1~50자여야 합니다")
        query: String,
        @RequestParam(name = "limit", defaultValue = "20") limit: Int,
    ): UserSearchResponse {
        return userService.search(selfId = principal.userId, query = query, limit = limit)
    }

    // 닉네임 가용 확인 — 본인 현재 닉네임은 항상 available=true (false positive 방지).
    @GetMapping("/check-display-name")
    fun checkDisplayName(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @RequestParam("displayName")
        @NotBlank(message = "displayName 은 필수입니다")
        @Size(min = 1, max = 50, message = "displayName 은 1~50자여야 합니다")
        displayName: String,
    ): DisplayNameCheckResponse {
        return userService.checkDisplayName(userId = principal.userId, displayName = displayName)
    }
}
