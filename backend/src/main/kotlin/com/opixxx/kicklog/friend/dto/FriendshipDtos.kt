package com.opixxx.kicklog.friend.dto

import com.opixxx.kicklog.friend.entity.FriendshipStatus
import com.opixxx.kicklog.friend.service.AcceptFriendshipResult
import com.opixxx.kicklog.friend.service.CreateFriendshipCommand
import com.opixxx.kicklog.friend.service.CreateFriendshipResult
import com.opixxx.kicklog.friend.service.FriendshipSummary
import com.opixxx.kicklog.friend.service.PendingFriendshipSummary
import com.opixxx.kicklog.friend.service.UserSummary
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Positive
import java.time.Instant

data class CreateFriendshipRequest(
    @field:Pattern(regexp = "^[A-Za-z0-9]{8}$", message = "초대 토큰은 8자 영문/숫자여야 합니다")
    val token: String? = null,

    @field:Positive(message = "대상 사용자 ID는 양수여야 합니다")
    val targetUserId: Long? = null,
) {
    fun toCommand(): CreateFriendshipCommand {
        return CreateFriendshipCommand(token = token, targetUserId = targetUserId)
    }
}

data class AcceptFriendshipRequest(
    @field:Pattern(regexp = "^accept$", message = "친구 요청 액션이 올바르지 않습니다")
    val action: String? = null,
)

data class FriendshipListResponse(
    val friends: List<FriendshipResponse>,
)

data class PendingFriendshipListResponse(
    val requests: List<PendingFriendshipResponse>,
)

data class FriendshipResponse(
    val friendshipId: Long,
    val user: FriendUserResponse,
    val acceptedAt: Instant?,
) {
    companion object {
        fun from(summary: FriendshipSummary): FriendshipResponse {
            return FriendshipResponse(
                friendshipId = summary.friendshipId,
                user = FriendUserResponse.from(summary.user),
                acceptedAt = summary.acceptedAt,
            )
        }
    }
}

data class PendingFriendshipResponse(
    val friendshipId: Long,
    val from: FriendUserResponse,
    val createdAt: Instant,
) {
    companion object {
        fun from(summary: PendingFriendshipSummary): PendingFriendshipResponse {
            return PendingFriendshipResponse(
                friendshipId = summary.friendshipId,
                from = FriendUserResponse.from(summary.from),
                createdAt = summary.createdAt,
            )
        }
    }
}

data class FriendUserResponse(
    val id: Long,
    val displayName: String,
) {
    companion object {
        fun from(summary: UserSummary): FriendUserResponse {
            return FriendUserResponse(id = summary.id, displayName = summary.displayName)
        }
    }
}

data class CreateFriendshipResponse(
    val friendshipId: Long,
    val status: String,
    val initiatedByMe: Boolean,
) {
    companion object {
        fun from(result: CreateFriendshipResult): CreateFriendshipResponse {
            return CreateFriendshipResponse(
                friendshipId = result.friendshipId,
                status = result.status.responseValue(),
                initiatedByMe = result.initiatedByMe,
            )
        }
    }
}

data class AcceptFriendshipResponse(
    val friendshipId: Long,
    val status: String,
    val acceptedAt: Instant?,
) {
    companion object {
        fun from(result: AcceptFriendshipResult): AcceptFriendshipResponse {
            return AcceptFriendshipResponse(
                friendshipId = result.friendshipId,
                status = result.status.responseValue(),
                acceptedAt = result.acceptedAt,
            )
        }
    }
}

private fun FriendshipStatus.responseValue(): String = name.lowercase()
