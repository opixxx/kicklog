package com.opixxx.kicklog.friend.repository

import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.entity.FriendshipStatus
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface FriendshipRepository : JpaRepository<Friendship, Long> {
    fun findByUserLowIdAndUserHighId(userLowId: Long, userHighId: Long): Friendship?

    @Query(
        """
        select f from Friendship f
        where (f.userLowId = :userId or f.userHighId = :userId)
          and f.status = :status
        order by f.acceptedAt desc, f.id desc
        """,
    )
    fun findAllByParticipantAndStatus(
        @Param("userId") userId: Long,
        @Param("status") status: FriendshipStatus,
    ): List<Friendship>

    @Query(
        """
        select f from Friendship f
        where (f.userLowId = :userId or f.userHighId = :userId)
          and f.status = com.opixxx.kicklog.friend.entity.FriendshipStatus.PENDING
          and f.initiatedById <> :userId
        order by f.createdAt desc, f.id desc
        """,
    )
    fun findReceivedPending(@Param("userId") userId: Long): List<Friendship>
}
