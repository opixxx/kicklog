package com.opixxx.kicklog.friend.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.FriendInvitation
import com.opixxx.kicklog.friend.repository.InMemoryFriendInvitationRepository
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class InvitationServiceTest {

    private val clock = Clock.fixed(Instant.parse("2026-05-23T09:00:00Z"), ZoneOffset.UTC)
    private val invitationRepository = InMemoryFriendInvitationRepository()
    private val userRepository = InMemoryUserRepository()
    private val properties = InvitationProperties(baseUrl = "https://kicklog.org/i")
    private val service = InvitationService(
        invitationRepository,
        userRepository,
        FixedInvitationTokenGenerator("Abc12345"),
        properties,
        clock,
    )

    @Test
    fun `8자 base62 토큰과 15일 만료 초대를 생성한다`() {
        val inviter = saveUser("초대자")

        val invitation = service.create(inviter.id)

        assertEquals("Abc12345", invitation.token)
        assertEquals("https://kicklog.org/i/Abc12345", invitation.url)
        assertEquals(Instant.parse("2026-06-07T09:00:00Z"), invitation.expiresAt)
        assertEquals(0, invitation.useCount)
    }

    @Test
    fun `주입된 baseUrl 을 그대로 사용해 초대 URL 을 만든다`() {
        val customService = InvitationService(
            invitationRepository,
            userRepository,
            FixedInvitationTokenGenerator("Custom01"),
            InvitationProperties(baseUrl = "https://example.test/i"),
            clock,
        )
        val inviter = saveUser("외부화검증")

        val invitation = customService.create(inviter.id)

        assertEquals("https://example.test/i/Custom01", invitation.url)
    }

    @Test
    fun `baseUrl 끝의 슬래시는 정규화된다`() {
        val trailingSlashService = InvitationService(
            invitationRepository,
            userRepository,
            FixedInvitationTokenGenerator("Slash001"),
            InvitationProperties(baseUrl = "https://kicklog.org/i/"),
            clock,
        )
        val inviter = saveUser("슬래시검증")

        val invitation = trailingSlashService.create(inviter.id)

        assertEquals("https://kicklog.org/i/Slash001", invitation.url)
    }

    @Test
    fun `토큰으로 초대 미리보기를 조회한다`() {
        val inviter = saveUser("초대자")
        invitationRepository.save(invitation(inviter.id, "Abc12345"))

        val preview = service.getByToken("Abc12345")

        assertEquals(inviter.id, preview.inviter.id)
        assertTrue(preview.valid)
    }

    @Test
    fun `활성 초대 목록만 조회한다`() {
        val inviter = saveUser("초대자")
        invitationRepository.save(invitation(inviter.id, "Active12"))
        invitationRepository.save(invitation(inviter.id, "Expired1", expiresAt = Instant.parse("2026-05-23T08:59:59Z")))
        invitationRepository.save(invitation(inviter.id, "Revoked1", revokedAt = clock.instant()))

        val invitations = service.listActive(inviter.id)

        assertEquals(listOf("Active12"), invitations.map { it.token })
    }

    @Test
    fun `소유자는 초대 링크를 폐기한다`() {
        val inviter = saveUser("초대자")
        val invitation = invitationRepository.save(invitation(inviter.id, "Revoke12"))

        service.revoke(inviter.id, invitation.id)

        assertTrue(invitationRepository.findByToken("Revoke12")!!.isRevoked())
    }

    @Test
    fun `없는 토큰 조회는 실패한다`() {
        val exception = assertFailsWith<KickLogException> {
            service.getByToken("Missing1")
        }

        assertEquals(ErrorCode.INVITATION_NOT_FOUND, exception.errorCode)
    }

    @Test
    fun `만료된 토큰 조회는 실패한다`() {
        val inviter = saveUser("초대자")
        invitationRepository.save(invitation(inviter.id, "Expired1", expiresAt = Instant.parse("2026-05-23T08:59:59Z")))

        val exception = assertFailsWith<KickLogException> {
            service.getByToken("Expired1")
        }

        assertEquals(ErrorCode.INVITATION_EXPIRED, exception.errorCode)
    }

    @Test
    fun `폐기된 토큰 조회는 실패한다`() {
        val inviter = saveUser("초대자")
        invitationRepository.save(invitation(inviter.id, "Revoked1", revokedAt = clock.instant()))

        val exception = assertFailsWith<KickLogException> {
            service.getByToken("Revoked1")
        }

        assertEquals(ErrorCode.INVITATION_REVOKED, exception.errorCode)
    }

    @Test
    fun `비소유자는 초대 링크를 폐기할 수 없다`() {
        val inviter = saveUser("초대자")
        val outsider = saveUser("비소유자")
        val invitation = invitationRepository.save(invitation(inviter.id, "Owned123"))

        val exception = assertFailsWith<KickLogException> {
            service.revoke(outsider.id, invitation.id)
        }

        assertEquals(ErrorCode.INVITATION_NOT_OWNED, exception.errorCode)
    }

    private fun saveUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun invitation(
        inviterId: Long,
        token: String,
        expiresAt: Instant = Instant.parse("2026-06-07T09:00:00Z"),
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
