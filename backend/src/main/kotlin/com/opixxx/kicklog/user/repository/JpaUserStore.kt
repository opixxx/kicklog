package com.opixxx.kicklog.user.repository

import com.opixxx.kicklog.user.entity.User
import org.springframework.data.domain.PageRequest
import org.springframework.stereotype.Repository
import java.time.Instant

@Repository
class JpaUserStore(
    private val userRepository: UserRepository,
) : UserStore {
    override fun save(user: User): User = userRepository.save(user)

    override fun findById(id: Long): User? = userRepository.findById(id).orElse(null)

    override fun searchByDisplayName(query: String, limit: Int, excludeUserId: Long): List<User> {
        return userRepository.searchActiveByDisplayName(
            query = query,
            excludeUserId = excludeUserId,
            pageable = PageRequest.of(0, limit),
        )
    }

    override fun findExpiredDeleted(cutoff: Instant): List<User> {
        return userRepository.findAllByDeletedAtBefore(cutoff)
    }

    override fun delete(user: User) {
        userRepository.delete(user)
    }

    override fun findAllActiveByIds(ids: Collection<Long>): List<User> {
        return if (ids.isEmpty()) emptyList() else userRepository.findAllByIdInAndDeletedAtIsNull(ids)
    }

    override fun findActiveByDisplayName(displayName: String): User? {
        return userRepository.findFirstByDisplayNameAndDeletedAtIsNull(displayName)
    }
}
