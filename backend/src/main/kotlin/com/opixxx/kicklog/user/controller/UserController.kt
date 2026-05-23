package com.opixxx.kicklog.user.controller

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.common.security.KickLogPrincipal
import com.opixxx.kicklog.user.dto.UserResponse
import com.opixxx.kicklog.user.repository.UserStore
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/users")
class UserController(
    private val userStore: UserStore,
) {
    @GetMapping("/me")
    fun me(@AuthenticationPrincipal principal: KickLogPrincipal): UserResponse {
        val user = userStore.findById(principal.userId)
            ?.takeUnless { it.isDeleted() }
            ?: throw KickLogException(ErrorCode.USER_NOT_FOUND)
        return UserResponse.from(user)
    }
}
