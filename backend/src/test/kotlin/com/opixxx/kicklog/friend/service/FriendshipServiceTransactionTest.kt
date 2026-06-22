package com.opixxx.kicklog.friend.service

import com.opixxx.kicklog.friend.repository.InMemoryFriendshipRepository
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import kotlin.test.Test
import kotlin.test.assertFailsWith

/**
 * EXEC_PLAN 2026-06-10 audit-fixes P3 —
 * FriendshipService.runInTransaction 의 침묵 무트랜잭션 분기 제거.
 *
 * 기존 [FriendshipServiceTest] 는 transactionTemplate 없이 request() 를 호출하므로
 * 본 변경 적용 후 GREEN 단계에서 함께 transactionTemplate 주입으로 갱신되어야 한다
 * (RED 보고에 충돌 명시).
 *
 * 본 테스트는 트랜잭션이 필요한 경로(request)에서 transactionTemplate 이 미주입(null)이면
 * 침묵하지 않고 명시적으로 IllegalStateException 으로 실패하는지를 검증한다.
 */
class FriendshipServiceTransactionTest {

    private val userRepository = InMemoryUserRepository()
    private val friendshipRepository = InMemoryFriendshipRepository()

    // transactionTemplate 미주입(null) — 트랜잭션 필요 경로에서 명시적 실패해야 한다.
    private val service = FriendshipService(
        friendshipRepository = friendshipRepository,
        userRepository = userRepository,
    )

    @Test
    fun `transactionTemplate 미주입 상태에서 request 를 호출하면 IllegalStateException 으로 명시 실패한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")

        assertFailsWith<IllegalStateException> {
            service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))
        }
    }

    private fun saveUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }
}
