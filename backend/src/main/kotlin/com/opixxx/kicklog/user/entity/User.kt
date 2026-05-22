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
    val id: Long = 0,

    @Column(name = "apple_user_id")
    var appleUserId: String? = null,

    @Column(nullable = false, unique = true, length = 50)
    var username: String,

    @Column(name = "display_name", nullable = false, length = 100)
    var displayName: String,

    @Column
    var email: String? = null,

    @Column(name = "hide_heart_rate", nullable = false)
    var hideHeartRate: Boolean = false,

    @Column(name = "created_at", nullable = false)
    val createdAt: Instant = Instant.now(),

    @Column(name = "updated_at", nullable = false)
    var updatedAt: Instant = Instant.now(),

    @Column(name = "deleted_at")
    var deletedAt: Instant? = null,
)
