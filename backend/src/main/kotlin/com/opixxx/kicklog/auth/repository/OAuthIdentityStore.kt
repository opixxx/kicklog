package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.OAuthIdentity
import com.opixxx.kicklog.auth.entity.OAuthProvider

interface OAuthIdentityStore {
    fun save(identity: OAuthIdentity): OAuthIdentity
    fun findByProviderAndProviderUserId(provider: OAuthProvider, providerUserId: String): OAuthIdentity?
}
