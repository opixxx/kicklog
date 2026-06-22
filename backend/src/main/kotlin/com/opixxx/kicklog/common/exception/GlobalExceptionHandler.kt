package com.opixxx.kicklog.common.exception

import jakarta.servlet.http.HttpServletRequest
import jakarta.validation.ConstraintViolationException
import org.slf4j.MDC
import org.springframework.http.HttpStatusCode
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.MissingServletRequestParameterException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice

data class ErrorResponse(
    val code: String,
    val message: String,
    val path: String,
    // 요청별 추적 ID (TraceIdFilter 가 MDC 에 주입) — 로그 상관관계용. 필드 추가만 (api-spec 계약).
    val traceId: String? = null,
)

@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(KickLogException::class)
    fun handleKickLogException(
        exception: KickLogException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        val message = exception.message ?: exception.errorCode.message
        return errorResponse(exception.errorCode.status, exception.errorCode.name, message, request)
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(
        exception: MethodArgumentNotValidException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        // @AssertTrue 등 클래스 레벨 cross-field 검증은 globalErrors 로 분류된다 — fieldErrors 만 보면 메시지가 누락된다.
        val message = exception.bindingResult.fieldErrors.firstOrNull()?.defaultMessage
            ?: exception.bindingResult.globalErrors.firstOrNull()?.defaultMessage
            ?: ErrorCode.VALIDATION_FAILED.message
        return validationError(message, request)
    }

    @ExceptionHandler(MissingServletRequestParameterException::class)
    fun handleMissingRequestParameter(
        exception: MissingServletRequestParameterException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        return validationError("${exception.parameterName} 파라미터는 필수입니다", request)
    }

    @ExceptionHandler(ConstraintViolationException::class)
    fun handleConstraintViolation(
        exception: ConstraintViolationException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        val message = exception.constraintViolations.firstOrNull()?.message
            ?: ErrorCode.VALIDATION_FAILED.message
        return validationError(message, request)
    }

    private fun validationError(message: String, request: HttpServletRequest): ResponseEntity<ErrorResponse> {
        return errorResponse(ErrorCode.VALIDATION_FAILED.status, ErrorCode.VALIDATION_FAILED.name, message, request)
    }

    private fun errorResponse(
        status: HttpStatusCode,
        code: String,
        message: String,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        return ResponseEntity
            .status(status)
            .body(ErrorResponse(code, message, request.requestURI, traceId = MDC.get("traceId")))
    }
}
