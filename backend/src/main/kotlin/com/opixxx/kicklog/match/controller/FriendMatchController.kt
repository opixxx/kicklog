package com.opixxx.kicklog.match.controller

import com.opixxx.kicklog.common.dto.CursorResponse
import com.opixxx.kicklog.common.security.KickLogPrincipal
import com.opixxx.kicklog.match.dto.MatchDetailResponse
import com.opixxx.kicklog.match.dto.MatchSummaryResponse
import com.opixxx.kicklog.match.service.MatchService
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/users/{userId}/matches")
class FriendMatchController(
    private val matchService: MatchService,
) {
    @GetMapping
    fun list(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable userId: Long,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "20") size: Int,
    ): CursorResponse<MatchSummaryResponse> {
        val page = matchService.listFriendMatches(principal.userId, userId, cursor, size)
        return CursorResponse(
            content = page.content.map(MatchSummaryResponse::from),
            size = page.size,
            nextCursor = page.nextCursor,
            hasNext = page.hasNext,
        )
    }

    @GetMapping("/{matchId}")
    fun get(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable userId: Long,
        @PathVariable matchId: Long,
    ): MatchDetailResponse {
        return MatchDetailResponse.from(matchService.getFriendMatch(principal.userId, userId, matchId))
    }
}
