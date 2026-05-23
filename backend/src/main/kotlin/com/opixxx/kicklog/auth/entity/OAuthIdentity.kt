package com.opixxx.kicklog.auth.entity

import com.opixxx.kicklog.user.entity.User
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "oauth_identities")
class OAuthIdentity(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long = 0,

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    var user: User,

    @Column(name = "provider", nullable = false, length = 20)
    var provider: OAuthProvider,

    @Column(name = "provider_user_id", nullable = false)
    var providerUserId: String,

    @Column(name = "email")
    var email: String? = null,

    @Column(name = "linked_at", nullable = false)
    var linkedAt: Instant = Instant.now(),
)
