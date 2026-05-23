package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.FriendInvitation
import org.springframework.data.jpa.repository.JpaRepository
import java.time.Instant

interface FriendInvitationRepository : JpaRepository<FriendInvitation, Long> {
    fun findByToken(token: String): FriendInvitation?
    fun existsByToken(token: String): Boolean
    fun findAllByInviterIdAndRevokedAtIsNullAndExpiresAtAfterOrderByCreatedAtDescIdDesc(
        inviterId: Long,
        expiresAt: Instant,
    ): List<FriendInvitation>
}
