package com.opixxx.kicklog.friend.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

@Entity
@Table(name = "friendships")
class Friendship(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long = 0,

    @Column(name = "user_low_id", nullable = false)
    var userLowId: Long,

    @Column(name = "user_high_id", nullable = false)
    var userHighId: Long,

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    var status: FriendshipStatus,

    @Column(name = "initiated_by_id", nullable = false)
    var initiatedById: Long,

    @Column(name = "created_at", nullable = false)
    var createdAt: Instant = Instant.now(),

    @Column(name = "accepted_at")
    var acceptedAt: Instant? = null,

    @Column(name = "updated_at", nullable = false)
    var updatedAt: Instant = Instant.now(),
) {
    fun otherUserId(userId: Long): Long {
        return if (userLowId == userId) userHighId else userLowId
    }

    fun isParticipant(userId: Long): Boolean = userLowId == userId || userHighId == userId

    fun isInitiatedBy(userId: Long): Boolean = initiatedById == userId

    fun accept(now: Instant) {
        status = FriendshipStatus.ACCEPTED
        acceptedAt = now
        updatedAt = now
    }

    companion object {
        fun createPending(requesterId: Long, targetUserId: Long, now: Instant): Friendship {
            return Friendship(
                userLowId = min(requesterId, targetUserId),
                userHighId = max(requesterId, targetUserId),
                status = FriendshipStatus.PENDING,
                initiatedById = requesterId,
                createdAt = now,
                updatedAt = now,
            )
        }
    }
}
