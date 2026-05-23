package com.opixxx.kicklog.user.repository

import com.opixxx.kicklog.user.entity.User
import java.time.Instant

interface UserStore {
    fun save(user: User): User
    fun findById(id: Long): User?
    fun searchByDisplayName(query: String, limit: Int, excludeUserId: Long): List<User>
    fun findExpiredDeleted(cutoff: Instant): List<User>
    fun delete(user: User)
}
