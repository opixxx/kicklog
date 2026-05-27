package com.opixxx.kicklog.friend.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.repository.InMemoryFriendshipRepository
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class FriendshipAuthorizerTest {

    private val friendshipRepository = InMemoryFriendshipRepository()
    private val userRepository = InMemoryUserRepository()
    private val authorizer = FriendshipAuthorizer(friendshipRepository, userRepository)

    @Test
    fun `accepted 친구이면 통과한다`() {
        val viewer = saveUser("조회자")
        val friend = saveUser("친구")
        saveAcceptedFriendship(viewer.id, friend.id)

        // throw 없이 정상 종료 — 사이드이펙트만.
        authorizer.assertCanView(viewer.id, friend.id)
    }

    @Test
    fun `자기 자신 조회는 허용한다`() {
        val viewer = saveUser("본인")

        // 본인 조회는 friendship 검사 우회 + 활성 사용자 검증만 통과.
        authorizer.assertCanView(viewer.id, viewer.id)
    }

    @Test
    fun `대상 사용자가 없으면 USER_NOT_FOUND를 반환한다`() {
        val viewer = saveUser("조회자")

        val exception = assertFailsWith<KickLogException> {
            authorizer.assertCanView(viewer.id, 999L)
        }

        assertEquals(ErrorCode.USER_NOT_FOUND, exception.errorCode)
    }

    @Test
    fun `대상 사용자가 탈퇴 상태이면 USER_NOT_FOUND를 반환한다`() {
        val viewer = saveUser("조회자")
        val friend = saveUser("탈퇴친구").also { it.markDeleted(Instant.now()) }

        val exception = assertFailsWith<KickLogException> {
            authorizer.assertCanView(viewer.id, friend.id)
        }

        assertEquals(ErrorCode.USER_NOT_FOUND, exception.errorCode)
    }

    @Test
    fun `accepted 친구가 아니면 FRIEND_UNAUTHORIZED를 반환한다`() {
        val viewer = saveUser("조회자")
        val other = saveUser("비친구")

        val exception = assertFailsWith<KickLogException> {
            authorizer.assertCanView(viewer.id, other.id)
        }

        assertEquals(ErrorCode.FRIEND_UNAUTHORIZED, exception.errorCode)
    }

    private fun saveUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun saveAcceptedFriendship(userId: Long, targetUserId: Long) {
        val now = Instant.parse("2026-05-23T09:00:00Z")
        val friendship = Friendship.createPending(userId, targetUserId, now)
        friendship.accept(now)
        friendshipRepository.save(friendship)
    }
}
