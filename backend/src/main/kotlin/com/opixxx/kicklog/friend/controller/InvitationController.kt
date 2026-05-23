package com.opixxx.kicklog.friend.controller

import com.opixxx.kicklog.common.security.KickLogPrincipal
import com.opixxx.kicklog.friend.dto.InvitationListResponse
import com.opixxx.kicklog.friend.dto.InvitationPreviewResponse
import com.opixxx.kicklog.friend.dto.InvitationResponse
import com.opixxx.kicklog.friend.service.InvitationService
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.http.ResponseEntity.noContent
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/invitations")
class InvitationController(
    private val invitationService: InvitationService,
) {
    @PostMapping
    fun create(
        @AuthenticationPrincipal principal: KickLogPrincipal,
    ): ResponseEntity<InvitationResponse> {
        return ResponseEntity
            .status(HttpStatus.CREATED)
            .body(InvitationResponse.from(invitationService.create(principal.userId)))
    }

    @GetMapping("/{token}")
    fun getByToken(
        @PathVariable token: String,
    ): InvitationPreviewResponse {
        return InvitationPreviewResponse.from(invitationService.getByToken(token))
    }

    @GetMapping
    fun list(
        @AuthenticationPrincipal principal: KickLogPrincipal,
    ): InvitationListResponse {
        return InvitationListResponse(invitationService.listActive(principal.userId).map(InvitationResponse::from))
    }

    @DeleteMapping("/{id}")
    fun revoke(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable id: Long,
    ): ResponseEntity<Void> {
        invitationService.revoke(principal.userId, id)
        return noContent().build()
    }
}
