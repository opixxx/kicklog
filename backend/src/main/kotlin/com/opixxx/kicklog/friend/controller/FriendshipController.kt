package com.opixxx.kicklog.friend.controller

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.common.security.KickLogPrincipal
import com.opixxx.kicklog.friend.dto.AcceptFriendshipRequest
import com.opixxx.kicklog.friend.dto.AcceptFriendshipResponse
import com.opixxx.kicklog.friend.dto.CreateFriendshipRequest
import com.opixxx.kicklog.friend.dto.CreateFriendshipResponse
import com.opixxx.kicklog.friend.dto.FriendshipListResponse
import com.opixxx.kicklog.friend.dto.FriendshipResponse
import com.opixxx.kicklog.friend.dto.PendingFriendshipListResponse
import com.opixxx.kicklog.friend.dto.PendingFriendshipResponse
import com.opixxx.kicklog.friend.service.FriendshipService
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.http.ResponseEntity.noContent
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/friendships")
class FriendshipController(
    private val friendshipService: FriendshipService,
) {
    @GetMapping
    fun list(
        @AuthenticationPrincipal principal: KickLogPrincipal,
    ): FriendshipListResponse {
        return FriendshipListResponse(
            friends = friendshipService.listAccepted(principal.userId).map(FriendshipResponse::from),
        )
    }

    @GetMapping("/pending")
    fun listPending(
        @AuthenticationPrincipal principal: KickLogPrincipal,
    ): PendingFriendshipListResponse {
        return PendingFriendshipListResponse(
            requests = friendshipService.listReceivedPending(principal.userId).map(PendingFriendshipResponse::from),
        )
    }

    @PostMapping
    fun create(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @Valid @RequestBody request: CreateFriendshipRequest,
    ): ResponseEntity<CreateFriendshipResponse> {
        val result = friendshipService.request(principal.userId, request.toCommand())
        return ResponseEntity.status(HttpStatus.CREATED).body(CreateFriendshipResponse.from(result))
    }

    @PatchMapping("/{id}")
    fun accept(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable id: Long,
        @Valid @RequestBody request: AcceptFriendshipRequest,
    ): AcceptFriendshipResponse {
        if (request.action != "accept") {
            throw KickLogException(ErrorCode.FRIEND_INVALID_REQUEST)
        }
        return AcceptFriendshipResponse.from(friendshipService.accept(principal.userId, id))
    }

    @DeleteMapping("/{id}")
    fun delete(
        @AuthenticationPrincipal principal: KickLogPrincipal,
        @PathVariable id: Long,
    ): ResponseEntity<Void> {
        friendshipService.delete(principal.userId, id)
        return noContent().build()
    }
}
