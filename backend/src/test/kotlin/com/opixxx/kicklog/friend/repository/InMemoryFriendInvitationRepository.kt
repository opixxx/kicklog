package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.FriendInvitation

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

    override fun findByToken(token: String): FriendInvitation? {
        return invitations.values.firstOrNull { it.token == token }
    }
}
