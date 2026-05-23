package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.FriendInvitation

interface FriendInvitationStore {
    fun save(invitation: FriendInvitation): FriendInvitation
    fun findByToken(token: String): FriendInvitation?
}
