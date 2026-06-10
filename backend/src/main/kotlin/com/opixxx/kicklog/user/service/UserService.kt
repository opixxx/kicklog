package com.opixxx.kicklog.user.service

import com.opixxx.kicklog.auth.repository.RefreshTokenStore
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.user.dto.DisplayNameCheckResponse
import com.opixxx.kicklog.user.dto.UserResponse
import com.opixxx.kicklog.user.dto.UserSearchResponse
import com.opixxx.kicklog.user.repository.UserStore
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Clock
import java.time.Duration
import java.time.Instant

@Service
class UserService(
    private val userStore: UserStore,
    private val refreshTokenRepository: RefreshTokenStore,
    private val clock: Clock,
) {

    @Transactional(readOnly = true)
    fun getMe(userId: Long): UserResponse {
        return UserResponse.from(requireActiveUser(userId))
    }

    @Transactional
    fun updateMe(userId: Long, displayName: String): UserResponse {
        val user = requireActiveUser(userId)
        val normalized = displayName.trim()
        // 본인 현재 닉네임과 동일하면 중복 검사 skip (false positive 방지).
        if (normalized != user.displayName) {
            assertDisplayNameAvailable(normalized)
        }
        user.updateProfile(displayName = normalized, now = Instant.now(clock))
        return try {
            UserResponse.from(userStore.save(user))
        } catch (exception: DataIntegrityViolationException) {
            // DB 레벨 race — 응용 검사 통과 후 동시에 다른 트랜잭션이 같은 닉네임 점유.
            throw KickLogException(ErrorCode.DISPLAY_NAME_DUPLICATE, cause = exception)
        }
    }

    @Transactional(readOnly = true)
    fun checkDisplayName(userId: Long, displayName: String): DisplayNameCheckResponse {
        val user = requireActiveUser(userId)
        val normalized = displayName.trim()
        // 본인 현재 닉네임이면 항상 사용 가능 (false positive 방지).
        if (normalized == user.displayName) {
            return DisplayNameCheckResponse(available = true)
        }
        val existing = userStore.findActiveByDisplayName(normalized)
        return DisplayNameCheckResponse(available = existing == null)
    }

    private fun assertDisplayNameAvailable(displayName: String) {
        if (userStore.findActiveByDisplayName(displayName) != null) {
            throw KickLogException(ErrorCode.DISPLAY_NAME_DUPLICATE)
        }
    }

    @Transactional
    fun softDelete(userId: Long) {
        val user = requireActiveUser(userId)
        user.markDeleted(now = Instant.now(clock))
        userStore.save(user)
        revokeAllRefreshTokens(userId)
    }

    @Transactional
    fun cancelDeletion(userId: Long): UserResponse {
        val user = userStore.findById(userId)
            ?: throw KickLogException(ErrorCode.USER_NOT_FOUND)
        if (!user.isDeleted()) {
            throw KickLogException(ErrorCode.USER_NOT_DELETING)
        }
        user.cancelDeletion(now = Instant.now(clock))
        return UserResponse.from(userStore.save(user))
    }

    @Transactional(readOnly = true)
    fun search(selfId: Long, query: String, limit: Int): UserSearchResponse {
        val normalizedLimit = limit.coerceIn(MIN_SEARCH_LIMIT, MAX_SEARCH_LIMIT)
        val users = userStore.searchByDisplayName(
            query = query,
            limit = normalizedLimit,
            excludeUserId = selfId,
        )
        return UserSearchResponse.from(users)
    }

    @Transactional
    fun purgeExpired(now: Instant): Int {
        val cutoff = now.minus(SOFT_DELETE_GRACE)
        val expired = userStore.findExpiredDeleted(cutoff)
        expired.forEach(userStore::delete)
        return expired.size
    }

    private fun requireActiveUser(userId: Long): com.opixxx.kicklog.user.entity.User {
        val user = userStore.findById(userId)
            ?: throw KickLogException(ErrorCode.USER_NOT_FOUND)
        if (user.isDeleted()) {
            throw KickLogException(ErrorCode.USER_DELETED)
        }
        return user
    }

    private fun revokeAllRefreshTokens(userId: Long) {
        refreshTokenRepository.findActiveByUserId(userId).forEach { token ->
            token.revoke()
            refreshTokenRepository.save(token)
        }
    }

    companion object {
        private const val MIN_SEARCH_LIMIT = 1
        private const val MAX_SEARCH_LIMIT = 50
        private val SOFT_DELETE_GRACE: Duration = Duration.ofDays(30)
    }
}
