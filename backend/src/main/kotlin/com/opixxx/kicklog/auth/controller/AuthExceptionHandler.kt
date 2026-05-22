package com.opixxx.kicklog.auth.controller

import com.opixxx.kicklog.auth.service.AuthException
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice

data class ErrorResponse(
    val code: String,
    val message: String,
    val field: String? = null,
)

@RestControllerAdvice
class AuthExceptionHandler {
    @ExceptionHandler(AuthException::class)
    fun handleAuthException(exception: AuthException): ResponseEntity<ErrorResponse> =
        ResponseEntity
            .status(exception.status)
            .body(ErrorResponse(code = exception.code, message = exception.message))

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidationException(exception: MethodArgumentNotValidException): ResponseEntity<ErrorResponse> {
        val fieldError = exception.bindingResult.fieldErrors.firstOrNull()
        return ResponseEntity
            .badRequest()
            .body(
                ErrorResponse(
                    code = "VALIDATION_FAILED",
                    message = fieldError?.defaultMessage ?: "요청 값이 올바르지 않습니다",
                    field = fieldError?.field,
                ),
            )
    }
}
