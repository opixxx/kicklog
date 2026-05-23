package com.opixxx.kicklog.user.repository

import com.opixxx.kicklog.user.entity.User
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.time.Instant

interface UserRepository : JpaRepository<User, Long> {

    @Query(
        """
        SELECT u FROM User u
         WHERE u.deletedAt IS NULL
           AND u.id <> :excludeUserId
           AND LOWER(u.displayName) LIKE LOWER(CONCAT('%', :query, '%'))
         ORDER BY u.id ASC
        """,
    )
    fun searchActiveByDisplayName(
        @Param("query") query: String,
        @Param("excludeUserId") excludeUserId: Long,
        pageable: Pageable,
    ): List<User>

    fun findAllByDeletedAtBefore(cutoff: Instant): List<User>
}
