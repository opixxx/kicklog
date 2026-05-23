package com.opixxx.kicklog.user.repository

import com.opixxx.kicklog.user.entity.User

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

    fun count(): Int = users.size
}
