package com.opixxx.kicklog.common.security

import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties(prefix = "kicklog.jwt")
data class JwtProperties(
    val secret: String,
    val issuer: String = "kicklog",
    val audience: String = "kicklog-ios",
    val accessTokenMinutes: Long = 15,
    val refreshTokenDays: Long = 30,
)
