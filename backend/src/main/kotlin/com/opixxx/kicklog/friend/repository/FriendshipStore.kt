package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.entity.FriendshipStatus

interface FriendshipStore {
    fun save(friendship: Friendship): Friendship
    fun findById(id: Long): Friendship?
    fun findByPair(userLowId: Long, userHighId: Long): Friendship?
    fun findAllByParticipantAndStatus(userId: Long, status: FriendshipStatus): List<Friendship>
    fun findReceivedPending(userId: Long): List<Friendship>
    fun delete(friendship: Friendship)
}
