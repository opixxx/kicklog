package com.opixxx.kicklog.friend.service

class FixedInvitationTokenGenerator(
    private vararg val tokens: String,
) : InvitationTokenGenerator {
    private var index = 0

    override fun generate(): String {
        val token = tokens.getOrElse(index) { tokens.last() }
        index += 1
        return token
    }
}
