package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.entity.FriendshipStatus

class InMemoryFriendshipRepository : FriendshipStore {
    private val friendships = linkedMapOf<Long, Friendship>()
    private var sequence = 1L

    override fun save(friendship: Friendship): Friendship {
        if (friendship.id == 0L) {
            friendship.id = sequence++
        }
        friendships[friendship.id] = friendship
        return friendship
    }

    override fun findById(id: Long): Friendship? = friendships[id]

    override fun findByPair(userLowId: Long, userHighId: Long): Friendship? {
        return friendships.values.firstOrNull { it.userLowId == userLowId && it.userHighId == userHighId }
    }

    override fun findAllByParticipantAndStatus(userId: Long, status: FriendshipStatus): List<Friendship> {
        return friendships.values
            .filter { it.isParticipant(userId) && it.status == status }
            .sortedWith(compareByDescending<Friendship> { it.acceptedAt }.thenByDescending { it.id })
    }

    override fun findReceivedPending(userId: Long): List<Friendship> {
        return friendships.values
            .filter { it.isParticipant(userId) && it.status == FriendshipStatus.PENDING && !it.isInitiatedBy(userId) }
            .sortedWith(compareByDescending<Friendship> { it.createdAt }.thenByDescending { it.id })
    }

    override fun delete(friendship: Friendship) {
        friendships.remove(friendship.id)
    }

    fun count(): Int = friendships.size
}
