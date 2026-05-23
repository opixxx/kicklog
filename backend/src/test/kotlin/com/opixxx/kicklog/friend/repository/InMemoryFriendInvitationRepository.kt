package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.FriendInvitation
import java.time.Instant

class InMemoryFriendInvitationRepository : FriendInvitationStore {
    private val invitations = linkedMapOf<Long, FriendInvitation>()
    private var sequence = 1L

    override fun save(invitation: FriendInvitation): FriendInvitation {
        if (invitation.id == 0L) {
            invitation.id = sequence++
        }
        invitations[invitation.id] = invitation
        return invitation
    }

    override fun findById(id: Long): FriendInvitation? = invitations[id]

    override fun findByToken(token: String): FriendInvitation? {
        return invitations.values.firstOrNull { it.token == token }
    }

    override fun existsByToken(token: String): Boolean {
        return invitations.values.any { it.token == token }
    }

    override fun findActiveByInviterId(inviterId: Long, now: Instant): List<FriendInvitation> {
        return invitations.values
            .filter { it.inviterId == inviterId && !it.isRevoked() && !it.isExpired(now) }
            .sortedWith(compareByDescending<FriendInvitation> { it.createdAt }.thenByDescending { it.id })
    }
}
