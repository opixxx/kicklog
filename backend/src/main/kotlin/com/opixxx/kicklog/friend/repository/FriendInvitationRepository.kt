package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.FriendInvitation
import org.springframework.data.jpa.repository.JpaRepository

interface FriendInvitationRepository : JpaRepository<FriendInvitation, Long> {
    fun findByToken(token: String): FriendInvitation?
}
