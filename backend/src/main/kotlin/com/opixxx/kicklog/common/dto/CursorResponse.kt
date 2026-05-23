package com.opixxx.kicklog.common.dto

data class CursorResponse<T>(
    val content: List<T>,
    val size: Int,
    val nextCursor: String?,
    val hasNext: Boolean,
)
