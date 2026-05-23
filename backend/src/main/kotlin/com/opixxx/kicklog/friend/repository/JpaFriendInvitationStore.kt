package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.FriendInvitation
import org.springframework.stereotype.Repository

@Repository
class JpaFriendInvitationStore(
    private val friendInvitationRepository: FriendInvitationRepository,
) : FriendInvitationStore {
    override fun save(invitation: FriendInvitation): FriendInvitation = friendInvitationRepository.save(invitation)

    override fun findByToken(token: String): FriendInvitation? = friendInvitationRepository.findByToken(token)
}
