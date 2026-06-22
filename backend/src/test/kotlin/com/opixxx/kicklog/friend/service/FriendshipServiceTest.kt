package com.opixxx.kicklog.friend.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.FriendshipStatus
import com.opixxx.kicklog.friend.repository.InMemoryFriendshipRepository
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import org.springframework.transaction.support.SimpleTransactionStatus
import org.springframework.transaction.support.TransactionCallback
import org.springframework.transaction.support.TransactionTemplate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class FriendshipServiceTest {

    private val userRepository = InMemoryUserRepository()
    private val friendshipRepository = InMemoryFriendshipRepository()

    // 단위 테스트용 스텁 — 실제 트랜잭션 없이 콜백만 그대로 실행한다.
    private val transactionTemplate = object : TransactionTemplate() {
        override fun <T : Any?> execute(action: TransactionCallback<T>): T =
            action.doInTransaction(SimpleTransactionStatus())
    }

    private val service = FriendshipService(
        friendshipRepository = friendshipRepository,
        userRepository = userRepository,
        transactionTemplate = transactionTemplate,
    )

    @Test
    fun `targetUserId로 친구 요청을 생성한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")

        val result = service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        assertEquals(FriendshipStatus.PENDING, result.status)
        assertTrue(result.initiatedByMe)
        assertEquals(1, friendshipRepository.count())
    }

    @Test
    fun `받은 친구 요청을 수락한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        val requested = service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        val accepted = service.accept(recipient.id, requested.friendshipId)

        assertEquals(FriendshipStatus.ACCEPTED, accepted.status)
    }

    @Test
    fun `내가 받은 pending 요청만 조회한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        val pending = service.listReceivedPending(recipient.id)

        assertEquals(listOf(requester.id), pending.map { it.from.id })
    }

    @Test
    fun `수락된 친구 관계만 친구 목록에서 조회한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        val requested = service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))
        service.accept(recipient.id, requested.friendshipId)

        val friends = service.listAccepted(requester.id)

        assertEquals(listOf(recipient.id), friends.map { it.user.id })
    }

    @Test
    fun `친구 관계를 삭제한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        val requested = service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        service.delete(requester.id, requested.friendshipId)

        assertEquals(emptyList(), service.listReceivedPending(recipient.id))
    }

    @Test
    fun `자기 자신에게 친구 요청하면 거부한다`() {
        val requester = saveUser("요청자")

        val exception = assertFailsWith<KickLogException> {
            service.request(requester.id, CreateFriendshipCommand(targetUserId = requester.id))
        }

        assertEquals(ErrorCode.FRIEND_SELF_REQUEST, exception.errorCode)
    }

    // EXEC_PLAN 2026-05-28 p1-display-name-unique — token 분기 폐기 후 회귀 단위.
    // CreateFriendshipCommand 가 targetUserId 단독 필드 (token 필드 제거) 인 상태에서도 정상 동작해야 한다.
    @Test
    fun `targetUserId 단독 호출 - token 분기 제거 후 회귀`() {
        val requester = saveUser("회귀요청자")
        val recipient = saveUser("회귀수신자")

        val result = service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        assertEquals(FriendshipStatus.PENDING, result.status)
        assertTrue(result.initiatedByMe)
        assertEquals(1, friendshipRepository.count())
    }

    @Test
    fun `이미 같은 방향 pending 요청이 있으면 중복 요청을 거부한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        val exception = assertFailsWith<KickLogException> {
            service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))
        }

        assertEquals(ErrorCode.FRIEND_ALREADY_EXISTS, exception.errorCode)
    }

    @Test
    fun `상대가 보낸 pending 요청이 있으면 자동 수락한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        val result = service.request(recipient.id, CreateFriendshipCommand(targetUserId = requester.id))

        assertEquals(FriendshipStatus.ACCEPTED, result.status)
    }

    @Test
    fun `보낸 요청을 직접 수락하면 거부한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        val requested = service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        val exception = assertFailsWith<KickLogException> {
            service.accept(requester.id, requested.friendshipId)
        }

        assertEquals(ErrorCode.FRIEND_NOT_RECIPIENT, exception.errorCode)
    }

    @Test
    fun `비당사자가 이미 수락된 친구 관계를 수락해도 상태를 노출하지 않는다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        val outsider = saveUser("비당사자")
        val requested = service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))
        service.accept(recipient.id, requested.friendshipId)

        val exception = assertFailsWith<KickLogException> {
            service.accept(outsider.id, requested.friendshipId)
        }

        assertEquals(ErrorCode.FRIEND_NOT_RECIPIENT, exception.errorCode)
    }

    @Test
    fun `비당사자가 친구 관계를 삭제하면 거부한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")
        val outsider = saveUser("비당사자")
        val requested = service.request(requester.id, CreateFriendshipCommand(targetUserId = recipient.id))

        val exception = assertFailsWith<KickLogException> {
            service.delete(outsider.id, requested.friendshipId)
        }

        assertEquals(ErrorCode.FRIEND_NOT_PARTICIPANT, exception.errorCode)
    }

    private fun saveUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }
}
