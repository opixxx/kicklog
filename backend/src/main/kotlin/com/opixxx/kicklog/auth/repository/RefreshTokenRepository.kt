package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.RefreshToken
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface RefreshTokenRepository : JpaRepository<RefreshToken, UUID>
