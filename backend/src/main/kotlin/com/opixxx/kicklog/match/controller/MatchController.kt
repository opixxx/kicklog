package com.opixxx.kicklog.match.controller

import com.opixxx.kicklog.common.dto.CursorResponse
import com.opixxx.kicklog.common.security.KickLogPrincipal
import com.opixxx.kicklog.match.dto.MatchDetailResponse
import com.opixxx.kicklog.match.dto.MatchSummaryResponse
import com.opixxx.kicklog.match.dto.UpsertMatchRequest
import com.opixxx.kicklog.match.service.MatchService
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.http.ResponseEntity.noContent
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.util.UUID

@RestController
@RequestMapping("/matches")
class MatchController(
    private val matchService: MatchService,
) {
    @PutMapping("/{clientMatchId}")
    fun upsert(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable clientMatchId: UUID,
        @Valid @RequestBody request: UpsertMatchRequest,
    ): ResponseEntity<MatchDetailResponse> {
        val result = matchService.saveMatch(principal.userId, clientMatchId, request.toCommand())
        val status = if (result.updated) HttpStatus.OK else HttpStatus.CREATED
        return ResponseEntity.status(status).body(MatchDetailResponse.from(result.match))
    }

    @GetMapping("/{matchId}")
    fun get(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable matchId: Long,
    ): MatchDetailResponse {
        return MatchDetailResponse.from(matchService.getMyMatch(principal.userId, matchId))
    }

    @GetMapping("/by-client-id/{clientMatchId}")
    fun getByClientId(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable clientMatchId: UUID,
    ): MatchDetailResponse {
        return MatchDetailResponse.from(matchService.getMyMatchByClientId(principal.userId, clientMatchId))
    }

    @DeleteMapping("/{matchId}")
    fun delete(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable matchId: Long,
    ): ResponseEntity<Void> {
        matchService.deleteMyMatch(principal.userId, matchId)
        return noContent().build()
    }

    @GetMapping
    fun list(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "20") size: Int,
    ): CursorResponse<MatchSummaryResponse> {
        val page = matchService.listMyMatches(principal.userId, cursor, size)
        return CursorResponse(
            content = page.content.map(MatchSummaryResponse::from),
            size = page.size,
            nextCursor = page.nextCursor,
            hasNext = page.hasNext,
        )
    }
}
