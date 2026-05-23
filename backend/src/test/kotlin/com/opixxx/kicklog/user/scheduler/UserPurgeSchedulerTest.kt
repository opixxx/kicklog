package com.opixxx.kicklog.user.scheduler

import com.opixxx.kicklog.auth.repository.InMemoryRefreshTokenRepository
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import com.opixxx.kicklog.user.service.UserService
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class UserPurgeSchedulerTest {

    private val userRepository = InMemoryUserRepository()
    private val refreshTokenRepository = InMemoryRefreshTokenRepository()
    private val fixedNow: Instant = Instant.parse("2026-05-23T04:00:00Z")
    private val clock: Clock = Clock.fixed(fixedNow, ZoneOffset.UTC)
    private val userService = UserService(
        userStore = userRepository,
        refreshTokenRepository = refreshTokenRepository,
        clock = clock,
    )
    private val scheduler = UserPurgeScheduler(userService = userService, clock = clock)

    @Test
    fun `30일을 초과한 deletedAt 사용자는 hard delete 된다`() {
        // 31일 전에 삭제된 사용자
        val old = userRepository.save(User.create(displayName = "오래전삭제", email = null))
        old.deletedAt = fixedNow.minusSeconds(31L * 24 * 60 * 60)
        userRepository.save(old)

        scheduler.purgeDeletedUsers()

        assertNull(userRepository.findById(old.id))
    }

    @Test
    fun `30일 이내의 deletedAt 사용자는 보존된다`() {
        val recent = userRepository.save(User.create(displayName = "최근삭제", email = null))
        recent.deletedAt = fixedNow.minusSeconds(29L * 24 * 60 * 60)
        userRepository.save(recent)

        scheduler.purgeDeletedUsers()

        assertNotNull(userRepository.findById(recent.id))
    }

    @Test
    fun `deletedAt 이 null 인 활성 사용자는 보존된다`() {
        val alive = userRepository.save(User.create(displayName = "활성", email = null))

        scheduler.purgeDeletedUsers()

        assertNotNull(userRepository.findById(alive.id))
    }

    @Test
    fun `여러 사용자 중 cutoff 기준으로 분기한다`() {
        val expired1 = userRepository.save(User.create(displayName = "만료1", email = null))
        expired1.deletedAt = fixedNow.minusSeconds(40L * 24 * 60 * 60)
        userRepository.save(expired1)

        val expired2 = userRepository.save(User.create(displayName = "만료2", email = null))
        expired2.deletedAt = fixedNow.minusSeconds(60L * 24 * 60 * 60)
        userRepository.save(expired2)

        val recent = userRepository.save(User.create(displayName = "최근", email = null))
        recent.deletedAt = fixedNow.minusSeconds(10L * 24 * 60 * 60)
        userRepository.save(recent)

        val alive = userRepository.save(User.create(displayName = "활성", email = null))

        scheduler.purgeDeletedUsers()

        assertNull(userRepository.findById(expired1.id))
        assertNull(userRepository.findById(expired2.id))
        assertNotNull(userRepository.findById(recent.id))
        assertNotNull(userRepository.findById(alive.id))
        assertEquals(2, userRepository.count())
    }
}
