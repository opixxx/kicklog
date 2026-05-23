package com.opixxx.kicklog.user.scheduler

import com.opixxx.kicklog.user.service.UserService
import org.slf4j.LoggerFactory
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import java.time.Clock
import java.time.Instant

@Component
class UserPurgeScheduler(
    private val userService: UserService,
    private val clock: Clock,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Scheduled(cron = "0 0 4 * * *")
    fun purgeDeletedUsers() {
        val purged = userService.purgeExpired(now = Instant.now(clock))
        if (purged > 0) {
            log.info("30일 경과 사용자 {}명 hard delete 완료", purged)
        }
    }
}
