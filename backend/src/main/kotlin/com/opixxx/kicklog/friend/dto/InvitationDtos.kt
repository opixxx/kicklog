package com.opixxx.kicklog.friend.dto

import com.opixxx.kicklog.friend.service.InvitationPreview
import com.opixxx.kicklog.friend.service.InvitationResult
import com.opixxx.kicklog.friend.service.UserSummary
import java.time.Instant

data class InvitationResponse(
    val id: Long,
    val token: String,
    val url: String,
    val expiresAt: Instant,
    val useCount: Int,
) {
    companion object {
        fun from(result: InvitationResult): InvitationResponse {
            return InvitationResponse(
                id = result.id,
                token = result.token,
                url = result.url,
                expiresAt = result.expiresAt,
                useCount = result.useCount,
            )
        }
    }
}

data class InvitationPreviewResponse(
    val token: String,
    val inviter: InvitationUserResponse,
    val expiresAt: Instant,
    val valid: Boolean,
) {
    companion object {
        fun from(preview: InvitationPreview): InvitationPreviewResponse {
            return InvitationPreviewResponse(
                token = preview.token,
                inviter = InvitationUserResponse.from(preview.inviter),
                expiresAt = preview.expiresAt,
                valid = preview.valid,
            )
        }
    }
}

data class InvitationListResponse(
    val invitations: List<InvitationResponse>,
)

data class InvitationUserResponse(
    val id: Long,
    val displayName: String,
) {
    companion object {
        fun from(summary: UserSummary): InvitationUserResponse {
            return InvitationUserResponse(id = summary.id, displayName = summary.displayName)
        }
    }
}
