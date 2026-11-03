package com.opixxx.kicklog.loadtest

import jakarta.validation.constraints.Min
import jakarta.validation.constraints.Positive

/**
 * 부하 테스트 하네스 DTO — 전부 `loadtest` 프로파일에서만 쓰인다 (prod 미존재).
 *
 * 흐름: Request → Command → (LoadTestSeedService) → Result → Response.
 */

// ── 토큰 발급 ────────────────────────────────────────────────────────────────

/** OAuth 우회로 발급한 access token 응답. */
data class LoadTestTokenResponse(
    val accessToken: String,
)

// ── 외부 의존 지연 (W-EXT) ───────────────────────────────────────────────────

/**
 * 외부 호출 1회의 결과. `elapsedMs` 는 **백엔드가 블로킹된 실제 시간**이다.
 *
 * 주입 지연(`upstreamDelayMs`)과 `elapsedMs` 의 차이가 큰 구간은 upstream 이 아니라
 * 백엔드 쪽에서 대기가 생긴 구간이다 — 스레드 포화의 1차 신호로 쓴다.
 */
data class LoadTestExternalResponse(
    val upstreamDelayMs: Int,
    val upstreamPid: Int,
    val elapsedMs: Long,
)

// ── DB 커넥션 점유 (W-DB-POOL) ───────────────────────────────────────────────

/**
 * DB 커넥션을 붙잡은 결과.
 *
 * `elapsedMs` 가 `requestedDelayMs` 보다 크게 벌어지면 그 차이가 **풀 대기 시간**이다 —
 * 커넥션이 없어 기다린 시간이므로, 풀이 구속 자원이 됐다는 직접 증거다.
 */
data class LoadTestDbResponse(
    val requestedDelayMs: Int,
    val elapsedMs: Long,
)

// ── 대량 시드 ────────────────────────────────────────────────────────────────

/**
 * 시드 요청. 빈 테이블로는 인덱스·집계 병목이 드러나지 않으므로 현실 규모 데이터를 만든다.
 *
 * @param userCount         생성할 사용자 수 (1 이상)
 * @param matchesPerUser    사용자당 매치 수 (0 이상)
 * @param quartersPerMatch  매치당 쿼터 수 (0 이상, 기본 4)
 * @param friendshipsPerUser 사용자당 친구 수 (0 이상, 기본 0 — 현재 미구현, 후속)
 */
data class LoadTestSeedRequest(
    @field:Positive(message = "userCount 는 1 이상이어야 합니다")
    val userCount: Int,
    @field:Min(value = 0, message = "matchesPerUser 는 0 이상이어야 합니다")
    val matchesPerUser: Int,
    @field:Min(value = 0, message = "quartersPerMatch 는 0 이상이어야 합니다")
    val quartersPerMatch: Int = 4,
    @field:Min(value = 0, message = "friendshipsPerUser 는 0 이상이어야 합니다")
    val friendshipsPerUser: Int = 0,
) {
    fun toCommand(): LoadTestSeedCommand =
        LoadTestSeedCommand(
            userCount = userCount,
            matchesPerUser = matchesPerUser,
            quartersPerMatch = quartersPerMatch,
            friendshipsPerUser = friendshipsPerUser,
        )
}

/** 시드 결과 응답. */
data class LoadTestSeedResponse(
    val usersCreated: Int,
    val matchesCreated: Int,
    val quartersCreated: Int,
    val friendshipsCreated: Int,
    val seededUserIdFrom: Long,
    val seededUserIdTo: Long,
) {
    companion object {
        fun from(result: LoadTestResult): LoadTestSeedResponse =
            LoadTestSeedResponse(
                usersCreated = result.usersCreated,
                matchesCreated = result.matchesCreated,
                quartersCreated = result.quartersCreated,
                friendshipsCreated = result.friendshipsCreated,
                seededUserIdFrom = result.seededUserIdFrom,
                seededUserIdTo = result.seededUserIdTo,
            )
    }
}

// ── 서비스 계층 Command / Result ─────────────────────────────────────────────

data class LoadTestSeedCommand(
    val userCount: Int,
    val matchesPerUser: Int,
    val quartersPerMatch: Int = 4,
    val friendshipsPerUser: Int = 0,
)

data class LoadTestResult(
    val usersCreated: Int,
    val matchesCreated: Int,
    val quartersCreated: Int,
    val friendshipsCreated: Int,
    val seededUserIdFrom: Long,
    val seededUserIdTo: Long,
)
