package com.opixxx.kicklog.auth.service

data class OAuthUserInfo(
    val providerUserId: String,
    val email: String?,
    val displayName: String?,
)
