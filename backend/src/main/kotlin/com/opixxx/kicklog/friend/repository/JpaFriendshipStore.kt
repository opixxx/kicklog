package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.entity.FriendshipStatus
import org.springframework.stereotype.Repository

@Repository
class JpaFriendshipStore(
    private val friendshipRepository: FriendshipRepository,
) : FriendshipStore {
    override fun save(friendship: Friendship): Friendship = friendshipRepository.saveAndFlush(friendship)

    override fun findById(id: Long): Friendship? = friendshipRepository.findById(id).orElse(null)

    override fun findByPair(userLowId: Long, userHighId: Long): Friendship? {
        return friendshipRepository.findByUserLowIdAndUserHighId(userLowId, userHighId)
    }

    override fun findAllByParticipantAndStatus(userId: Long, status: FriendshipStatus): List<Friendship> {
        return friendshipRepository.findAllByParticipantAndStatus(userId, status)
    }

    override fun findReceivedPending(userId: Long): List<Friendship> {
        return friendshipRepository.findReceivedPending(userId)
    }

    override fun delete(friendship: Friendship) {
        friendshipRepository.delete(friendship)
    }
}
