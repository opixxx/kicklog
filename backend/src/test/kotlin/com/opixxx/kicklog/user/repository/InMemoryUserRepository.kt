package com.opixxx.kicklog.user.repository

import com.opixxx.kicklog.user.entity.User
import java.time.Instant

class InMemoryUserRepository : UserStore {
    private val users = linkedMapOf<Long, User>()
    private var sequence = 1L

    override fun save(user: User): User {
        if (user.id == 0L) {
            user.id = sequence++
        }
        users[user.id] = user
        return user
    }

    override fun findById(id: Long): User? = users[id]

    override fun searchByDisplayName(query: String, limit: Int, excludeUserId: Long): List<User> {
        // 부분 일치(대소문자 무시) + 본인 제외 + deleted 제외 + limit 으로 자르기
        val normalized = query.trim().lowercase()
        return users.values
            .asSequence()
            .filter { it.id != excludeUserId }
            .filter { !it.isDeleted() }
            .filter { it.displayName.lowercase().contains(normalized) }
            .take(limit)
            .toList()
    }

    override fun findExpiredDeleted(cutoff: Instant): List<User> {
        return users.values.filter { user ->
            val deletedAt = user.deletedAt ?: return@filter false
            deletedAt.isBefore(cutoff)
        }
    }

    override fun delete(user: User) {
        users.remove(user.id)
    }

    override fun findAllActiveByIds(ids: Collection<Long>): List<User> {
        return ids.mapNotNull(users::get).filterNot(User::isDeleted)
    }

    override fun findActiveByDisplayName(displayName: String): User? {
        return users.values.firstOrNull { it.displayName == displayName && !it.isDeleted() }
    }

    fun count(): Int = users.size
}
