package com.opixxx.kicklog.friend.service

import org.springframework.boot.context.properties.ConfigurationProperties

/**
 * 친구 초대 링크 URL 설정.
 *
 * application.yml 의 `kicklog.invitation.base-url` 로 주입한다.
 * 도메인 결정은 ADR-0007 (kicklog.org).
 */
@ConfigurationProperties(prefix = "kicklog.invitation")
data class InvitationProperties(
    /** 스킴 포함 절대 URL, 토큰 prefix 까지. 예: `https://kicklog.org/i` */
    val baseUrl: String,
) {
    init {
        require(baseUrl.isNotBlank()) { "kicklog.invitation.base-url 가 비어 있다" }
    }

    fun urlFor(token: String): String = "${baseUrl.trimEnd('/')}/$token"
}
