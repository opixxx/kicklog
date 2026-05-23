package com.opixxx.kicklog.friend.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.FriendInvitation
import com.opixxx.kicklog.friend.entity.FriendshipStatus
import com.opixxx.kicklog.friend.repository.InMemoryFriendInvitationRepository
import com.opixxx.kicklog.friend.repository.InMemoryFriendshipRepository
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class FriendshipServiceTest {

    private val userRepository = InMemoryUserRepository()
    private val friendshipRepository = InMemoryFriendshipRepository()
    private val invitationRepository = InMemoryFriendInvitationRepository()
    private val service = FriendshipService(friendshipRepository, userRepository, invitationRepository)

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

    @Test
    fun `token과 targetUserId가 둘 다 없으면 친구 요청을 거부한다`() {
        val requester = saveUser("요청자")

        val exception = assertFailsWith<KickLogException> {
            service.request(requester.id, CreateFriendshipCommand())
        }

        assertEquals(ErrorCode.FRIEND_INVALID_REQUEST, exception.errorCode)
    }

    @Test
    fun `token과 targetUserId가 둘 다 있으면 친구 요청을 거부한다`() {
        val requester = saveUser("요청자")
        val recipient = saveUser("상대")

        val exception = assertFailsWith<KickLogException> {
            service.request(requester.id, CreateFriendshipCommand(token = "xY9k2Lp4", targetUserId = recipient.id))
        }

        assertEquals(ErrorCode.FRIEND_INVALID_REQUEST, exception.errorCode)
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
    fun `초대 토큰으로 친구 요청을 생성한다`() {
        val requester = saveUser("요청자")
        val inviter = saveUser("초대자")
        invitationRepository.save(invitation(inviter.id, token = "Abc12345"))

        val result = service.request(requester.id, CreateFriendshipCommand(token = "Abc12345"))

        assertEquals(FriendshipStatus.PENDING, result.status)
        assertEquals(1, invitationRepository.findByToken("Abc12345")!!.useCount)
    }

    @Test
    fun `만료된 초대 토큰은 거부한다`() {
        val requester = saveUser("요청자")
        val inviter = saveUser("초대자")
        invitationRepository.save(invitation(inviter.id, token = "Expired1", expiresAt = Instant.now().minusSeconds(1)))

        val exception = assertFailsWith<KickLogException> {
            service.request(requester.id, CreateFriendshipCommand(token = "Expired1"))
        }

        assertEquals(ErrorCode.INVITATION_EXPIRED, exception.errorCode)
    }

    @Test
    fun `취소된 초대 토큰은 거부한다`() {
        val requester = saveUser("요청자")
        val inviter = saveUser("초대자")
        invitationRepository.save(invitation(inviter.id, token = "Revoked1", revokedAt = Instant.now()))

        val exception = assertFailsWith<KickLogException> {
            service.request(requester.id, CreateFriendshipCommand(token = "Revoked1"))
        }

        assertEquals(ErrorCode.INVITATION_REVOKED, exception.errorCode)
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

    private fun invitation(
        inviterId: Long,
        token: String,
        expiresAt: Instant = Instant.now().plus(15, ChronoUnit.DAYS),
        revokedAt: Instant? = null,
    ): FriendInvitation {
        return FriendInvitation(
            inviterId = inviterId,
            token = token,
            expiresAt = expiresAt,
            revokedAt = revokedAt,
        )
    }
}
