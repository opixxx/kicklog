package com.opixxx.kicklog.auth.scheduler

import com.opixxx.kicklog.auth.repository.RefreshTokenStore
import org.slf4j.LoggerFactory
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Transactional
import java.time.Clock
import java.time.Instant

/**
 * 만료된 RefreshToken 을 주기적으로 정리한다 (P2-1).
 *
 * 만료 기준은 `expiresAt < now` — revoked 여부 무관이다.
 * 만료된 토큰은 verify 단계에서 이미 거부되므로 재사용 탐지에 불필요하다.
 * UserPurgeScheduler(04:00) 와 30분 간격으로 분산 실행한다.
 */
@Component
class RefreshTokenPurgeScheduler(
    private val refreshTokenRepository: RefreshTokenStore,
    private val clock: Clock,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Scheduled(cron = "0 30 4 * * *")
    @Transactional
    fun purgeExpiredTokens() {
        val deleted = refreshTokenRepository.deleteAllExpiredBefore(now = Instant.now(clock))
        if (deleted > 0) {
            log.info("만료된 refresh token {}건 정리 완료", deleted)
        }
    }
}
