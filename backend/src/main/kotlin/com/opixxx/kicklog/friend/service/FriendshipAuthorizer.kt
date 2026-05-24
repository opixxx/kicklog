package com.opixxx.kicklog.friend.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.FriendshipStatus
import com.opixxx.kicklog.friend.repository.FriendshipStore
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserStore
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import kotlin.math.max
import kotlin.math.min

@Service
class FriendshipAuthorizer(
    private val friendshipRepository: FriendshipStore,
    private val userRepository: UserStore,
) {
    @Transactional(readOnly = true)
    fun assertCanView(viewerId: Long, targetUserId: Long): User {
        val targetUser = findActiveUser(targetUserId)
        if (viewerId == targetUserId) {
            return targetUser
        }

        val friendship = friendshipRepository.findByPair(min(viewerId, targetUserId), max(viewerId, targetUserId))
        if (friendship?.status != FriendshipStatus.ACCEPTED) {
            throw KickLogException(ErrorCode.FRIEND_UNAUTHORIZED)
        }
        return targetUser
    }

    private fun findActiveUser(userId: Long): User {
        return userRepository.findById(userId)?.takeUnless(User::isDeleted)
            ?: throw KickLogException(ErrorCode.USER_NOT_FOUND)
    }
}
