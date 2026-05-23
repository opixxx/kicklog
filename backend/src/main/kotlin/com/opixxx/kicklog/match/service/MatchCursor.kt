package com.opixxx.kicklog.match.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.match.repository.MatchCursorCondition
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.Base64

object MatchCursor {
    fun encode(playedAt: Instant, id: Long): String {
        val raw = "${playedAt}|$id"
        return Base64.getUrlEncoder().withoutPadding().encodeToString(raw.toByteArray(StandardCharsets.UTF_8))
    }

    fun decode(cursor: String?): MatchCursorCondition? {
        if (cursor.isNullOrBlank()) return null

        return runCatching {
            val raw = String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8)
            val parts = raw.split("|")
            MatchCursorCondition(playedAt = Instant.parse(parts[0]), id = parts[1].toLong())
        }.getOrElse {
            throw KickLogException(ErrorCode.VALIDATION_FAILED, "커서 값이 올바르지 않습니다")
        }
    }
}
