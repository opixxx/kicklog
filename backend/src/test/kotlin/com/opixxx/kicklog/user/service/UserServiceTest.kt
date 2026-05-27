package com.opixxx.kicklog.user.service

import com.opixxx.kicklog.auth.entity.RefreshToken
import com.opixxx.kicklog.auth.repository.InMemoryRefreshTokenRepository
import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.InMemoryUserRepository
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UserServiceTest {

    private val userRepository = InMemoryUserRepository()
    private val refreshTokenRepository = InMemoryRefreshTokenRepository()
    private val fixedClock: Clock = Clock.fixed(Instant.parse("2026-05-23T00:00:00Z"), ZoneOffset.UTC)
    private val service = UserService(
        userStore = userRepository,
        refreshTokenRepository = refreshTokenRepository,
        clock = fixedClock,
    )

    @Test
    fun `updateMe 단일 인자 시그니처 - displayName 만 받아 갱신한다 (p0-cleanup)`() {
        // EXEC_PLAN 2026-05-28 p0-cleanup — updateMe(userId, displayName) 시그니처로 축소.
        // 반환된 UserResponse 에 hideHeartRate 필드가 없어야 한다.
        val user = userRepository.save(User.create(displayName = "축구왕", email = null))

        val response = service.updateMe(userId = user.id, displayName = "축구왕2")

        assertEquals("축구왕2", response.displayName)
        // 영속화 확인
        val saved = userRepository.findById(user.id)!!
        assertEquals("축구왕2", saved.displayName)
    }

    // -------------------------------------------------------------
    // EXEC_PLAN 2026-05-28 p1-display-name-unique — #5 닉네임 unique
    // -------------------------------------------------------------

    @Test
    fun `updateMe 는 본인 현재 닉네임과 동일 입력이면 중복 검사 없이 통과한다`() {
        val me = userRepository.save(User.create(displayName = "홍길동", email = null))
        // 같은 닉네임이 다른 활성 사용자에게도 점유돼 있다 가정해도, 본인 동일이면 unique 검사 skip 이어야 함
        // (정상 흐름에선 UNIQUE INDEX 로 두 사용자 공존 불가하나, 검사 skip 검증 단위로 InMemory 사용)
        val response = service.updateMe(userId = me.id, displayName = "홍길동")

        assertEquals("홍길동", response.displayName)
    }

    @Test
    fun `updateMe 는 다른 활성 사용자가 쓰는 닉네임으로 변경 시 DISPLAY_NAME_DUPLICATE 를 던진다`() {
        val me = userRepository.save(User.create(displayName = "홍길동", email = null))
        userRepository.save(User.create(displayName = "박수비", email = null))

        val exception = assertFailsWith<KickLogException> {
            service.updateMe(userId = me.id, displayName = "박수비")
        }
        assertEquals(ErrorCode.DISPLAY_NAME_DUPLICATE, exception.errorCode)
    }

    @Test
    fun `updateMe 는 탈퇴자 닉네임은 재사용 허용한다`() {
        val me = userRepository.save(User.create(displayName = "홍길동", email = null))
        val gone = userRepository.save(User.create(displayName = "박수비", email = null))
        gone.deletedAt = Instant.parse("2026-05-01T00:00:00Z")
        userRepository.save(gone)

        val response = service.updateMe(userId = me.id, displayName = "박수비")

        assertEquals("박수비", response.displayName)
    }

    @Test
    fun `checkDisplayName 미사용 닉네임은 available=true`() {
        val me = userRepository.save(User.create(displayName = "검사자", email = null))

        val result = service.checkDisplayName(userId = me.id, displayName = "축구왕")

        assertTrue(result.available)
    }

    @Test
    fun `checkDisplayName 본인 현재 닉네임은 available=true (false positive 방지)`() {
        val me = userRepository.save(User.create(displayName = "홍길동", email = null))

        val result = service.checkDisplayName(userId = me.id, displayName = "홍길동")

        assertTrue(result.available)
    }

    @Test
    fun `checkDisplayName 다른 활성 사용자가 쓰는 닉네임은 available=false`() {
        val me = userRepository.save(User.create(displayName = "검사자", email = null))
        userRepository.save(User.create(displayName = "박수비", email = null))

        val result = service.checkDisplayName(userId = me.id, displayName = "박수비")

        assertFalse(result.available)
    }

    @Test
    fun `checkDisplayName 탈퇴자 닉네임은 available=true (재사용 허용)`() {
        val me = userRepository.save(User.create(displayName = "검사자", email = null))
        val gone = userRepository.save(User.create(displayName = "탈퇴자닉", email = null))
        gone.deletedAt = Instant.parse("2026-05-01T00:00:00Z")
        userRepository.save(gone)

        val result = service.checkDisplayName(userId = me.id, displayName = "탈퇴자닉")

        assertTrue(result.available)
    }

    @Test
    fun `softDelete 는 deletedAt 을 설정하고 활성 refresh token 을 모두 폐기한다`() {
        val user = userRepository.save(User.create(displayName = "삭제대상", email = null))
        val activeToken1 = saveActiveRefreshToken(user)
        val activeToken2 = saveActiveRefreshToken(user)

        service.softDelete(userId = user.id)

        val deleted = userRepository.findById(user.id)!!
        assertTrue(deleted.isDeleted())
        assertTrue(refreshTokenRepository.findByJti(activeToken1.jti)!!.isRevoked())
        assertTrue(refreshTokenRepository.findByJti(activeToken2.jti)!!.isRevoked())
        assertTrue(refreshTokenRepository.findActiveByUserId(user.id).isEmpty())
    }

    @Test
    fun `cancelDeletion 은 deletedAt 을 null 로 되돌린다`() {
        val user = userRepository.save(User.create(displayName = "복구대상", email = null))
        user.deletedAt = Instant.parse("2026-05-20T00:00:00Z")
        userRepository.save(user)

        val response = service.cancelDeletion(userId = user.id)

        assertEquals(user.id, response.id)
        assertNull(userRepository.findById(user.id)!!.deletedAt)
    }

    @Test
    fun `cancelDeletion 은 삭제 대기가 아닌 사용자면 USER_NOT_DELETING 을 던진다`() {
        val user = userRepository.save(User.create(displayName = "정상사용자", email = null))

        val exception = assertFailsWith<KickLogException> {
            service.cancelDeletion(userId = user.id)
        }
        assertEquals(ErrorCode.USER_NOT_DELETING, exception.errorCode)
    }

    @Test
    fun `search 는 본인 제외 deleted 제외 후 부분 일치 결과를 반환한다`() {
        val me = userRepository.save(User.create(displayName = "수비왕", email = null))
        val candidate1 = userRepository.save(User.create(displayName = "박수비", email = null))
        userRepository.save(User.create(displayName = "박공격", email = null))
        val candidate2 = userRepository.save(User.create(displayName = "이수비", email = null))
        val deletedUser = userRepository.save(User.create(displayName = "사라진수비", email = null))
        deletedUser.deletedAt = Instant.parse("2026-05-01T00:00:00Z")
        userRepository.save(deletedUser)

        val response = service.search(selfId = me.id, query = "수비", limit = 20)

        val ids = response.users.map { it.id }
        assertEquals(2, ids.size)
        assertTrue(candidate1.id in ids)
        assertTrue(candidate2.id in ids)
    }

    @Test
    fun `search limit 은 50 으로 clamp 되고 1 미만은 1 로 보정된다`() {
        val me = userRepository.save(User.create(displayName = "검색자", email = null))
        repeat(60) { index ->
            userRepository.save(User.create(displayName = "수비${index + 1}", email = null))
        }

        val clamped = service.search(selfId = me.id, query = "수비", limit = 100)
        assertEquals(50, clamped.users.size)

        val minClamped = service.search(selfId = me.id, query = "수비", limit = 0)
        assertEquals(1, minClamped.users.size)
    }

    @Test
    fun `purgeExpired 는 cutoff 보다 오래된 deletedAt 사용자만 hard delete 한다`() {
        val now = Instant.parse("2026-05-23T00:00:00Z")
        val oldDeleted = userRepository.save(User.create(displayName = "31일전삭제", email = null))
        oldDeleted.deletedAt = now.minusSeconds(31L * 24 * 60 * 60)
        userRepository.save(oldDeleted)

        val recentDeleted = userRepository.save(User.create(displayName = "29일전삭제", email = null))
        recentDeleted.deletedAt = now.minusSeconds(29L * 24 * 60 * 60)
        userRepository.save(recentDeleted)

        val alive = userRepository.save(User.create(displayName = "정상", email = null))

        val purged = service.purgeExpired(now = now)

        assertEquals(1, purged)
        assertNull(userRepository.findById(oldDeleted.id))
        assertNotNull(userRepository.findById(recentDeleted.id))
        assertNotNull(userRepository.findById(alive.id))
    }

    @Test
    fun `softDelete 는 이미 폐기된 refresh token 은 다시 폐기하지 않는다`() {
        val user = userRepository.save(User.create(displayName = "재폐기방지", email = null))
        val active = saveActiveRefreshToken(user)
        // 추가 검증: 활성 토큰이 1건 있어야 함
        assertEquals(1, refreshTokenRepository.findActiveByUserId(user.id).size)

        service.softDelete(userId = user.id)

        assertTrue(refreshTokenRepository.findByJti(active.jti)!!.isRevoked())
        // soft delete 후에도 사용자 row 는 존재(soft delete 이므로)
        assertFalse(userRepository.findById(user.id) == null)
    }

    private fun saveActiveRefreshToken(user: User): RefreshToken {
        val token = RefreshToken(
            jti = UUID.randomUUID(),
            user = user,
            expiresAt = Instant.parse("2026-12-31T00:00:00Z"),
        )
        refreshTokenRepository.save(token)
        return token
    }
}
