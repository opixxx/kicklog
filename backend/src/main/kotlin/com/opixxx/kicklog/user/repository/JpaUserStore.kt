package com.opixxx.kicklog.user.repository

import com.opixxx.kicklog.user.entity.User
import org.springframework.stereotype.Repository

@Repository
class JpaUserStore(
    private val userRepository: UserRepository,
) : UserStore {
    override fun save(user: User): User = userRepository.save(user)

    override fun findById(id: Long): User? = userRepository.findById(id).orElse(null)

    override fun findAllActiveByIds(ids: Collection<Long>): List<User> {
        return if (ids.isEmpty()) emptyList() else userRepository.findAllByIdInAndDeletedAtIsNull(ids)
    }
}
