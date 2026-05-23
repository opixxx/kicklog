package com.opixxx.kicklog.user.repository

import com.opixxx.kicklog.user.entity.User

interface UserStore {
    fun save(user: User): User
    fun findById(id: Long): User?
}
