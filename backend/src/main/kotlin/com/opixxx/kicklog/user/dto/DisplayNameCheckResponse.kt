package com.opixxx.kicklog.user.dto

// GET /users/check-display-name 응답.
// available=true: 사용 가능 (미사용 또는 본인 현재 닉네임 — false positive 방지).
// available=false: 다른 활성 사용자가 이미 사용 중.
data class DisplayNameCheckResponse(
    val available: Boolean,
)
