package com.opixxx.kicklog.user.repository

import com.opixxx.kicklog.user.entity.User
import org.springframework.data.jpa.repository.JpaRepository

interface UserRepository : JpaRepository<User, Long> {
    fun findAllByIdInAndDeletedAtIsNull(ids: Collection<Long>): List<User>
}
