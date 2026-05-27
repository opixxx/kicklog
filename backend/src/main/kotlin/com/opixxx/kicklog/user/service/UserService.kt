package com.opixxx.kicklog.user.service

import com.opixxx.kicklog.auth.repository.RefreshTokenStore
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.user.dto.UserResponse
import com.opixxx.kicklog.user.dto.UserSearchResponse
import com.opixxx.kicklog.user.repository.UserStore
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

    @Transactional
    fun updateMe(userId: Long, displayName: String): UserResponse {
        val user = requireActiveUser(userId)
        user.updateProfile(displayName = displayName, now = Instant.now(clock))
        return UserResponse.from(userStore.save(user))
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
