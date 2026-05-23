package com.opixxx.kicklog.friend.service

import org.springframework.stereotype.Component
import java.security.SecureRandom

interface InvitationTokenGenerator {
    fun generate(): String
}

@Component
class SecureInvitationTokenGenerator : InvitationTokenGenerator {
    private val random = SecureRandom()

    override fun generate(): String {
        return buildString(TOKEN_LENGTH) {
            repeat(TOKEN_LENGTH) {
                append(ALPHABET[random.nextInt(ALPHABET.length)])
            }
        }
    }

    companion object {
        private const val TOKEN_LENGTH = 8
        private const val ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    }
}
