package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.OAuthIdentity
import com.opixxx.kicklog.auth.entity.OAuthProvider

class InMemoryOAuthIdentityRepository : OAuthIdentityStore {
    private val identities = mutableListOf<OAuthIdentity>()
    private var sequence = 1L

    override fun save(identity: OAuthIdentity): OAuthIdentity {
        if (identity.id == 0L) {
            identity.id = sequence++
        }
        identities.removeIf { it.id == identity.id }
        identities.add(identity)
        return identity
    }

    override fun findByProviderAndProviderUserId(
        provider: OAuthProvider,
        providerUserId: String,
    ): OAuthIdentity? {
        return identities.firstOrNull { it.provider == provider && it.providerUserId == providerUserId }
    }
}
