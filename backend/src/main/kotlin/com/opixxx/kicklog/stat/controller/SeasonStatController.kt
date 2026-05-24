package com.opixxx.kicklog.stat.controller

import com.opixxx.kicklog.common.security.KickLogPrincipal
import com.opixxx.kicklog.stat.dto.SeasonStatResponse
import com.opixxx.kicklog.stat.service.SeasonStatService
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.validation.annotation.Validated
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/users")
@Validated
class SeasonStatController(
    private val seasonStatService: SeasonStatService,
) {
    @GetMapping("/me/seasons/{year}")
    fun getMySeason(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable @Min(2000, message = "연도는 2000 이상이어야 합니다")
        @Max(2100, message = "연도는 2100 이하이어야 합니다")
        year: Int,
    ): SeasonStatResponse {
        return SeasonStatResponse.from(seasonStatService.getMySeasonStat(principal.userId, year))
    }

    @GetMapping("/{userId}/seasons/{year}")
    fun getFriendSeason(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable userId: Long,
        @PathVariable @Min(2000, message = "연도는 2000 이상이어야 합니다")
        @Max(2100, message = "연도는 2100 이하이어야 합니다")
        year: Int,
    ): SeasonStatResponse {
        return SeasonStatResponse.from(seasonStatService.getFriendSeasonStat(principal.userId, userId, year))
    }
}
