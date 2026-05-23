package com.opixxx.kicklog.user.dto

import com.fasterxml.jackson.annotation.JsonIgnore
import jakarta.validation.constraints.AssertTrue
import jakarta.validation.constraints.Size

data class UpdateMeRequest(
    @field:Size(min = 1, max = 50, message = "displayName 은 1~50자여야 합니다")
    val displayName: String? = null,

    val hideHeartRate: Boolean? = null,
) {
    @JsonIgnore
    @AssertTrue(message = "displayName 또는 hideHeartRate 중 최소 하나는 필요합니다")
    fun hasAtLeastOneField(): Boolean = displayName != null || hideHeartRate != null
}
