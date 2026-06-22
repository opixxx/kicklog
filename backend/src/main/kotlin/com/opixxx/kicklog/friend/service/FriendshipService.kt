package com.opixxx.kicklog.friend.service

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.entity.FriendshipStatus
import com.opixxx.kicklog.friend.repository.FriendshipStore
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserStore
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionTemplate
import java.time.Clock
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

// 초대 링크 도메인 폐기 (P1 #4) — token 분기 제거. targetUserId 단독.
data class CreateFriendshipCommand(
    val targetUserId: Long,
)

data class UserSummary(
    val id: Long,
    val displayName: String,
)

data class FriendshipSummary(
    val friendshipId: Long,
    val user: UserSummary,
    val acceptedAt: Instant?,
)

data class PendingFriendshipSummary(
    val friendshipId: Long,
    val from: UserSummary,
    val createdAt: Instant,
)

data class CreateFriendshipResult(
    val friendshipId: Long,
    val status: FriendshipStatus,
    val initiatedByMe: Boolean,
    val acceptedAt: Instant?,
)

data class AcceptFriendshipResult(
    val friendshipId: Long,
    val status: FriendshipStatus,
    val acceptedAt: Instant?,
)

@Service
class FriendshipService(
    private val friendshipRepository: FriendshipStore,
    private val userRepository: UserStore,
    private val clock: Clock = Clock.systemUTC(),
    private val transactionTemplate: TransactionTemplate? = null,
) {
    @Transactional(readOnly = true)
    fun listAccepted(userId: Long): List<FriendshipSummary> {
        val friendships = friendshipRepository.findAllByParticipantAndStatus(userId, FriendshipStatus.ACCEPTED)
        val users = findActiveUsers(friendships.map { it.otherUserId(userId) })
        return friendships.mapNotNull { friendship -> toAcceptedSummary(friendship, userId, users) }
    }

    @Transactional(readOnly = true)
    fun listReceivedPending(userId: Long): List<PendingFriendshipSummary> {
        val friendships = friendshipRepository.findReceivedPending(userId)
        val users = findActiveUsers(friendships.map { it.initiatedById })
        return friendships.mapNotNull { friendship -> toPendingSummary(friendship, users) }
    }

    fun request(userId: Long, command: CreateFriendshipCommand): CreateFriendshipResult {
        return try {
            runInTransaction {
                requestInTransaction(userId, command)
            }
        } catch (exception: DataIntegrityViolationException) {
            runInTransaction {
                handleConflictInTransaction(userId, command, exception)
            }
        }
    }

    @Transactional
    fun accept(userId: Long, friendshipId: Long): AcceptFriendshipResult {
        val friendship = friendshipRepository.findById(friendshipId)
            ?: throw KickLogException(ErrorCode.FRIEND_NOT_FOUND)
        validateAcceptable(friendship, userId)
        friendship.accept(now())
        return toAcceptResult(friendshipRepository.save(friendship))
    }

    @Transactional
    fun delete(userId: Long, friendshipId: Long) {
        val friendship = friendshipRepository.findById(friendshipId)
            ?: throw KickLogException(ErrorCode.FRIEND_NOT_FOUND)
        if (!friendship.isParticipant(userId)) {
            throw KickLogException(ErrorCode.FRIEND_NOT_PARTICIPANT)
        }
        friendshipRepository.delete(friendship)
    }

    private fun requestInTransaction(userId: Long, command: CreateFriendshipCommand): CreateFriendshipResult {
        val targetUserId = command.targetUserId
        validateRequestUsers(userId, targetUserId)
        val existing = findExisting(userId, targetUserId)
        if (existing != null) {
            return handleExistingRequest(existing, userId)
        }
        val friendship = friendshipRepository.save(Friendship.createPending(userId, targetUserId, now()))
        return toCreateResult(friendship, userId)
    }

    private fun handleConflictInTransaction(
        userId: Long,
        command: CreateFriendshipCommand,
        cause: DataIntegrityViolationException,
    ): CreateFriendshipResult {
        val conflicted = findExisting(userId, command.targetUserId)
            ?: throw KickLogException(ErrorCode.FRIEND_ALREADY_EXISTS, cause = cause)
        return handleExistingRequest(conflicted, userId)
    }

    private fun validateRequestUsers(userId: Long, targetUserId: Long) {
        if (userId == targetUserId) {
            throw KickLogException(ErrorCode.FRIEND_SELF_REQUEST)
        }
        findActiveUser(userId)
        findActiveUser(targetUserId)
    }

    private fun handleExistingRequest(friendship: Friendship, userId: Long): CreateFriendshipResult {
        if (friendship.status == FriendshipStatus.ACCEPTED || friendship.isInitiatedBy(userId)) {
            throw KickLogException(ErrorCode.FRIEND_ALREADY_EXISTS)
        }
        friendship.accept(now())
        return toCreateResult(friendshipRepository.save(friendship), userId)
    }

    private fun validateAcceptable(friendship: Friendship, userId: Long) {
        if (!friendship.isParticipant(userId) || friendship.isInitiatedBy(userId)) {
            throw KickLogException(ErrorCode.FRIEND_NOT_RECIPIENT)
        }
        if (friendship.status == FriendshipStatus.ACCEPTED) {
            throw KickLogException(ErrorCode.FRIEND_ALREADY_ACCEPTED)
        }
    }

    private fun toAcceptedSummary(
        friendship: Friendship,
        userId: Long,
        users: Map<Long, User>,
    ): FriendshipSummary? {
        val other = users[friendship.otherUserId(userId)]
            ?: return null
        return FriendshipSummary(friendship.id, UserSummary(other.id, other.displayName), friendship.acceptedAt)
    }

    private fun toPendingSummary(
        friendship: Friendship,
        users: Map<Long, User>,
    ): PendingFriendshipSummary? {
        val from = users[friendship.initiatedById]
            ?: return null
        return PendingFriendshipSummary(friendship.id, UserSummary(from.id, from.displayName), friendship.createdAt)
    }

    private fun findExisting(userId: Long, targetUserId: Long): Friendship? {
        return friendshipRepository.findByPair(min(userId, targetUserId), max(userId, targetUserId))
    }

    private fun findActiveUser(userId: Long): User {
        return userRepository.findById(userId)?.takeUnless(User::isDeleted)
            ?: throw KickLogException(ErrorCode.USER_NOT_FOUND)
    }

    private fun findActiveUsers(userIds: Collection<Long>): Map<Long, User> {
        return userRepository.findAllActiveByIds(userIds.toSet()).associateBy(User::id)
    }

    private fun toCreateResult(friendship: Friendship, userId: Long): CreateFriendshipResult {
        return CreateFriendshipResult(friendship.id, friendship.status, friendship.isInitiatedBy(userId), friendship.acceptedAt)
    }

    private fun toAcceptResult(friendship: Friendship): AcceptFriendshipResult {
        return AcceptFriendshipResult(friendship.id, friendship.status, friendship.acceptedAt)
    }

    private fun now(): Instant = Instant.now(clock)

    private fun <T> runInTransaction(action: () -> T): T {
        val template = transactionTemplate
            ?: throw IllegalStateException("TransactionTemplate 미주입: 트랜잭션 경계 없이 실행할 수 없습니다")
        // execute 의 반환 타입이 T? 라 캐스트가 불가피 — action 이 T 를 반환하므로 안전하다.
        @Suppress("UNCHECKED_CAST")
        return template.execute { action() } as T
    }
}
