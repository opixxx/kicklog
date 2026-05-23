package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.FriendInvitation
import java.time.Instant

interface FriendInvitationStore {
    fun save(invitation: FriendInvitation): FriendInvitation
    fun findById(id: Long): FriendInvitation?
    fun findByToken(token: String): FriendInvitation?
    fun existsByToken(token: String): Boolean
    fun findActiveByInviterId(inviterId: Long, now: Instant): List<FriendInvitation>
}
