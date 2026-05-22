package com.opixxx.kicklog.auth.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import jakarta.persistence.UniqueConstraint
import java.time.Instant

@Entity
@Table(
    name = "oauth_identities",
    uniqueConstraints = [UniqueConstraint(columnNames = ["provider", "provider_user_id"])],
)
class OAuthIdentity(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0,

    @Column(name = "user_id", nullable = false)
    val userId: Long,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    val provider: OAuthProvider,

    @Column(name = "provider_user_id", nullable = false)
    val providerUserId: String,

    @Column
    val email: String? = null,

    @Column(name = "created_at", nullable = false)
    val createdAt: Instant = Instant.now(),
)
