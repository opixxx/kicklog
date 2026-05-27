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
    // 본인이거나 ACCEPTED 친구가 아니면 throw — 사이드이펙트만. 호출자는 권한 통과 후 본인 책임으로 대상 데이터를 조회한다.
    // (p0-cleanup 이전엔 hideHeartRate 마스킹용으로 User 를 반환했으나 정책 폐기 후 반환값 용도 없음.)
    // 검증 순서: 활성 사용자(USER_NOT_FOUND) → 친구 관계(FRIEND_UNAUTHORIZED). 탈퇴/미존재가 먼저 드러난다.
    @Transactional(readOnly = true)
    fun assertCanView(viewerId: Long, targetUserId: Long) {
        requireActiveUser(targetUserId)
        if (viewerId == targetUserId) {
            return
        }
        val friendship = friendshipRepository.findByPair(min(viewerId, targetUserId), max(viewerId, targetUserId))
        if (friendship?.status != FriendshipStatus.ACCEPTED) {
            throw KickLogException(ErrorCode.FRIEND_UNAUTHORIZED)
        }
    }

    private fun requireActiveUser(userId: Long) {
        val active = userRepository.findById(userId)?.takeUnless(User::isDeleted)
        if (active == null) {
            throw KickLogException(ErrorCode.USER_NOT_FOUND)
        }
    }
}
