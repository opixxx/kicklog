package com.opixxx.kicklog.friend.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.FriendInvitation
import com.opixxx.kicklog.friend.repository.FriendInvitationStore
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserStore
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionTemplate
import java.time.Clock
import java.time.Instant
import java.time.temporal.ChronoUnit

data class InvitationResult(
    val id: Long,
    val token: String,
    val url: String,
    val expiresAt: Instant,
    val useCount: Int,
)

data class InvitationPreview(
    val token: String,
    val inviter: UserSummary,
    val expiresAt: Instant,
    val valid: Boolean,
)

@Service
class InvitationService(
    private val invitationRepository: FriendInvitationStore,
    private val userRepository: UserStore,
    private val tokenGenerator: InvitationTokenGenerator,
    private val clock: Clock = Clock.systemUTC(),
    private val transactionTemplate: TransactionTemplate? = null,
) {
    fun create(inviterId: Long): InvitationResult {
        repeat(MAX_TOKEN_ATTEMPTS) {
            val token = tokenGenerator.generate()
            if (invitationRepository.existsByToken(token)) {
                return@repeat
            }
            try {
                return runInTransaction {
                    createInTransaction(inviterId, token)
                }
            } catch (exception: DataIntegrityViolationException) {
                return@repeat
            }
        }
        throw KickLogException(ErrorCode.INVITATION_TOKEN_GENERATION_FAILED)
    }

    @Transactional(readOnly = true)
    fun getByToken(token: String): InvitationPreview {
        val invitation = invitationRepository.findByToken(token)
            ?: throw KickLogException(ErrorCode.INVITATION_NOT_FOUND)
        validateUsable(invitation)
        val inviter = findActiveUser(invitation.inviterId)
        return InvitationPreview(invitation.token, UserSummary(inviter.id, inviter.displayName), invitation.expiresAt, true)
    }

    @Transactional(readOnly = true)
    fun listActive(inviterId: Long): List<InvitationResult> {
        findActiveUser(inviterId)
        return invitationRepository.findActiveByInviterId(inviterId, now()).map(::toResult)
    }

    @Transactional
    fun revoke(inviterId: Long, invitationId: Long) {
        val invitation = invitationRepository.findById(invitationId)
            ?: throw KickLogException(ErrorCode.INVITATION_NOT_FOUND)
        if (invitation.inviterId != inviterId) {
            throw KickLogException(ErrorCode.INVITATION_NOT_OWNED)
        }
        invitation.revoke(now())
        invitationRepository.save(invitation)
    }

    private fun newInvitation(inviterId: Long, token: String): FriendInvitation {
        val now = now()
        return FriendInvitation(
            inviterId = inviterId,
            token = token,
            expiresAt = now.plus(INVITATION_DAYS, ChronoUnit.DAYS),
            createdAt = now,
        )
    }

    private fun createInTransaction(inviterId: Long, token: String): InvitationResult {
        findActiveUser(inviterId)
        return toResult(invitationRepository.save(newInvitation(inviterId, token)))
    }

    private fun validateUsable(invitation: FriendInvitation) {
        if (invitation.isRevoked()) {
            throw KickLogException(ErrorCode.INVITATION_REVOKED)
        }
        if (invitation.isExpired(now())) {
            throw KickLogException(ErrorCode.INVITATION_EXPIRED)
        }
    }

    private fun findActiveUser(userId: Long): User {
        return userRepository.findById(userId)?.takeUnless(User::isDeleted)
            ?: throw KickLogException(ErrorCode.USER_NOT_FOUND)
    }

    private fun toResult(invitation: FriendInvitation): InvitationResult {
        return InvitationResult(
            id = invitation.id,
            token = invitation.token,
            url = "$INVITATION_BASE_URL/${invitation.token}",
            expiresAt = invitation.expiresAt,
            useCount = invitation.useCount,
        )
    }

    private fun now(): Instant = Instant.now(clock)

    private fun <T> runInTransaction(action: () -> T): T {
        return transactionTemplate?.execute { action() } ?: action()
    }

    companion object {
        private const val MAX_TOKEN_ATTEMPTS = 5
        private const val INVITATION_DAYS = 15L
        private const val INVITATION_BASE_URL = "https://kicklog.app/i"
    }
}
