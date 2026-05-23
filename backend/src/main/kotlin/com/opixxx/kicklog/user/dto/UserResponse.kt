package com.opixxx.kicklog.user.dto

import com.opixxx.kicklog.user.entity.User
import java.time.Instant

data class UserResponse(
    val id: Long,
    val displayName: String,
    val email: String?,
    val hideHeartRate: Boolean,
    val createdAt: Instant,
) {
    companion object {
        fun from(user: User): UserResponse {
            return UserResponse(
                id = user.id,
                displayName = user.displayName,
                email = user.email,
                hideHeartRate = user.hideHeartRate,
                createdAt = user.createdAt,
            )
        }
    }
}
