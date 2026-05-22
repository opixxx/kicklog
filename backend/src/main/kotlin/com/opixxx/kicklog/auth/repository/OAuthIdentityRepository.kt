package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.OAuthIdentity
import com.opixxx.kicklog.auth.entity.OAuthProvider
import org.springframework.data.jpa.repository.JpaRepository

interface OAuthIdentityRepository : JpaRepository<OAuthIdentity, Long> {
    fun findByProviderAndProviderUserId(provider: OAuthProvider, providerUserId: String): OAuthIdentity?
}
