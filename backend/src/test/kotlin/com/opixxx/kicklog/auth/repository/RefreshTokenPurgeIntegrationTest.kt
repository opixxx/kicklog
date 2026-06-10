package com.opixxx.kicklog.auth.repository

import com.opixxx.kicklog.auth.entity.RefreshToken
import com.opixxx.kicklog.friend.KickLogPostgresContainer
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserRepository
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * EXEC_PLAN 2026-06-10 audit-fixes P2-1 — 만료 RefreshToken 정리 스케줄러의 벌크 삭제 쿼리.
 *
 * RefreshTokenStore.deleteAllExpiredBefore(now) 는 @Modifying @Query 벌크 삭제이므로
 * 실제 PostgreSQL(Testcontainers + flyway)에서 검증한다. (H2 가 아닌 실 DB 동작 — 메모리 컨벤션)
 *
 * 만료 기준: expiresAt < now (revoked 여부 무관, expiresAt == now 는 보존).
 */
@SpringBootTest(
    properties = [
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate",
    ],
)
@Testcontainers(disabledWithoutDocker = true)
class RefreshTokenPurgeIntegrationTest {

    @Autowired
    private lateinit var refreshTokenRepository: RefreshTokenRepository

    @Autowired
    private lateinit var userRepository: UserRepository

    private val now: Instant = Instant.parse("2026-06-10T00:00:00Z")

    @Test
    fun `만료된 토큰만 삭제되고 유효한 토큰은 보존된다`() {
        val user = saveUser("토큰정리대상")
        val expired1 = saveToken(user, expiresAt = now.minusSeconds(3600))
        val expired2 = saveToken(user, expiresAt = now.minusSeconds(1))
        val valid = saveToken(user, expiresAt = now.plusSeconds(3600))

        val deleted = refreshTokenRepository.deleteAllExpiredBefore(now)

        assertEquals(2, deleted)
        assertNull(refreshTokenRepository.findByJti(expired1.jti))
        assertNull(refreshTokenRepository.findByJti(expired2.jti))
        assertNotNull(refreshTokenRepository.findByJti(valid.jti))
    }

    @Test
    fun `revoked 됐지만 미만료인 토큰은 보존된다`() {
        // 재사용 탐지를 위해 만료 전 revoked 토큰은 남겨야 한다.
        val user = saveUser("revoked미만료대상")
        val revokedButValid = saveToken(
            user,
            expiresAt = now.plusSeconds(3600),
            revokedAt = now.minusSeconds(60),
        )

        val deleted = refreshTokenRepository.deleteAllExpiredBefore(now)

        assertEquals(0, deleted)
        assertNotNull(refreshTokenRepository.findByJti(revokedButValid.jti))
    }

    @Test
    fun `expiresAt 이 now 와 정확히 같으면 삭제되지 않는다`() {
        // 경계값 — strict less than(<) 기준이므로 expiresAt == now 는 보존.
        val user = saveUser("경계값대상")
        val boundary = saveToken(user, expiresAt = now)

        val deleted = refreshTokenRepository.deleteAllExpiredBefore(now)

        assertEquals(0, deleted)
        assertNotNull(refreshTokenRepository.findByJti(boundary.jti))
    }

    private fun saveUser(displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    private fun saveToken(user: User, expiresAt: Instant, revokedAt: Instant? = null): RefreshToken {
        return refreshTokenRepository.save(
            RefreshToken(
                jti = UUID.randomUUID(),
                user = user,
                expiresAt = expiresAt,
                revokedAt = revokedAt,
                createdAt = now.minusSeconds(7200),
            ),
        )
    }

    companion object {
        @Container
        @JvmStatic
        val postgres = KickLogPostgresContainer()

        @DynamicPropertySource
        @JvmStatic
        fun datasource(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url", postgres::getJdbcUrl)
            registry.add("spring.datasource.username", postgres::getUsername)
            registry.add("spring.datasource.password", postgres::getPassword)
            registry.add("spring.datasource.driver-class-name", postgres::getDriverClassName)
        }
    }
}
