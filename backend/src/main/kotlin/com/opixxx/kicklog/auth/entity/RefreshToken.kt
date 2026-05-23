package com.opixxx.kicklog.auth.entity

import com.opixxx.kicklog.user.entity.User
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.FetchType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "refresh_tokens")
class RefreshToken(
    @Id
    @Column(name = "jti", nullable = false)
    var jti: UUID,

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    var user: User,

    @Column(name = "expires_at", nullable = false)
    var expiresAt: Instant,

    @Column(name = "revoked_at")
    var revokedAt: Instant? = null,

    @Column(name = "rotated_to_jti")
    var rotatedToJti: UUID? = null,

    @Column(name = "device_info")
    var deviceInfo: String? = null,

    @Column(name = "created_at", nullable = false)
    var createdAt: Instant = Instant.now(),

    @Column(name = "last_used_at")
    var lastUsedAt: Instant? = null,
) {
    fun isExpired(now: Instant = Instant.now()): Boolean = !expiresAt.isAfter(now)

    fun isRevoked(): Boolean = revokedAt != null

    fun isActive(now: Instant = Instant.now()): Boolean = !isRevoked() && !isExpired(now)

    fun rotateTo(newJti: UUID, now: Instant = Instant.now()) {
        revokedAt = now
        rotatedToJti = newJti
        lastUsedAt = now
    }

    fun revoke(now: Instant = Instant.now()) {
        revokedAt = revokedAt ?: now
    }
}
