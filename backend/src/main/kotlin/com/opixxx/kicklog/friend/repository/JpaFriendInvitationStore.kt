package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.FriendInvitation
import org.springframework.stereotype.Repository
import java.time.Instant

@Repository
class JpaFriendInvitationStore(
    private val friendInvitationRepository: FriendInvitationRepository,
) : FriendInvitationStore {
    override fun save(invitation: FriendInvitation): FriendInvitation = friendInvitationRepository.saveAndFlush(invitation)

    override fun findById(id: Long): FriendInvitation? = friendInvitationRepository.findById(id).orElse(null)

    override fun findByToken(token: String): FriendInvitation? = friendInvitationRepository.findByToken(token)

    override fun existsByToken(token: String): Boolean = friendInvitationRepository.existsByToken(token)

    override fun findActiveByInviterId(inviterId: Long, now: Instant): List<FriendInvitation> {
        return friendInvitationRepository
            .findAllByInviterIdAndRevokedAtIsNullAndExpiresAtAfterOrderByCreatedAtDescIdDesc(inviterId, now)
    }
}
