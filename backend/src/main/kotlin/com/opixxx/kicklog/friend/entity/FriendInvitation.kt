package com.opixxx.kicklog.friend.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "friend_invitations")
class FriendInvitation(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long = 0,

    @Column(name = "inviter_id", nullable = false)
    var inviterId: Long,

    @Column(name = "token", nullable = false, length = 8)
    var token: String,

    @Column(name = "expires_at", nullable = false)
    var expiresAt: Instant,

    @Column(name = "use_count", nullable = false)
    var useCount: Int = 0,

    @Column(name = "revoked_at")
    var revokedAt: Instant? = null,

    @Column(name = "created_at", nullable = false)
    var createdAt: Instant = Instant.now(),
) {
    fun isRevoked(): Boolean = revokedAt != null

    fun isExpired(now: Instant): Boolean = !expiresAt.isAfter(now)

    fun use() {
        useCount += 1
    }

    fun revoke(now: Instant) {
        revokedAt = now
    }
}
