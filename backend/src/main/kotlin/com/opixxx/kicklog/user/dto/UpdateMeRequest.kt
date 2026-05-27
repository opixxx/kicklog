package com.opixxx.kicklog.user.dto

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size

// 구버전 iOS 가 보내던 'hideHeartRate' 등 미사용 키를 무시한다 — Breaking Change 안전망.
// (Spring Boot 기본도 ignore 지만 미래 ObjectMapper 재구성에 영향받지 않도록 명시.)
// PATCH /users/me — displayName 단일 필드.
// 타입을 `String?` 으로 둔 이유: JSON `{}` 본문 시 Jackson 이 누락 키를 null 로 채울 수 있도록 허용하고,
// Bean Validation `@NotBlank` 가 null/빈/공백 모두 VALIDATION_FAILED 로 잡는다.
// (non-null `String` 으로 두면 누락 시 HttpMessageNotReadableException 으로 빠져 ErrorResponse 매핑이 누락된다 —
// GlobalExceptionHandler 에 별도 핸들러 추가가 필요해지므로 본 PR 범위 외.)
// Controller 호출 시점엔 `@NotBlank` 통과로 non-null 이 보장되어 force unwrap 한다.
@JsonIgnoreProperties(ignoreUnknown = true)
data class UpdateMeRequest(
    @field:NotBlank(message = "displayName 은 필수입니다")
    @field:Size(min = 1, max = 50, message = "displayName 은 1~50자여야 합니다")
    val displayName: String? = null,
)
