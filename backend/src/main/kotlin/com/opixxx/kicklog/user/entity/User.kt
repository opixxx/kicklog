package com.opixxx.kicklog.user.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "users")
class User(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long = 0,

    @Column(name = "display_name", nullable = false, length = 50)
    var displayName: String,

    @Column(name = "email")
    var email: String? = null,

    @Column(name = "created_at", nullable = false)
    var createdAt: Instant = Instant.now(),

    @Column(name = "updated_at", nullable = false)
    var updatedAt: Instant = Instant.now(),

    @Column(name = "deleted_at")
    var deletedAt: Instant? = null,
) {
    fun isDeleted(): Boolean = deletedAt != null

    fun updateProfile(displayName: String, now: Instant) {
        this.displayName = displayName
        this.updatedAt = now
    }

    fun markDeleted(now: Instant) {
        this.deletedAt = now
        this.updatedAt = now
    }

    fun cancelDeletion(now: Instant) {
        this.deletedAt = null
        this.updatedAt = now
    }

    companion object {
        fun create(displayName: String, email: String?): User {
            return User(displayName = displayName.takeIf { it.isNotBlank() } ?: "사용자", email = email)
        }
    }
}
