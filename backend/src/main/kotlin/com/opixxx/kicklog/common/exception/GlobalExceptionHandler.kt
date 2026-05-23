package com.opixxx.kicklog.common.exception

import jakarta.servlet.http.HttpServletRequest
import jakarta.validation.ConstraintViolationException
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.MissingServletRequestParameterException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice

data class ErrorResponse(
    val code: String,
    val message: String,
    val path: String,
)

@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(KickLogException::class)
    fun handleKickLogException(
        exception: KickLogException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        return ResponseEntity
            .status(exception.errorCode.status)
            .body(ErrorResponse(exception.errorCode.name, exception.message ?: exception.errorCode.message, request.requestURI))
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(
        exception: MethodArgumentNotValidException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        val message = exception.bindingResult.fieldErrors.firstOrNull()?.defaultMessage
            ?: ErrorCode.VALIDATION_FAILED.message
        return ResponseEntity
            .status(ErrorCode.VALIDATION_FAILED.status)
            .body(ErrorResponse(ErrorCode.VALIDATION_FAILED.name, message, request.requestURI))
    }

    @ExceptionHandler(MissingServletRequestParameterException::class)
    fun handleMissingRequestParameter(
        exception: MissingServletRequestParameterException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        return ResponseEntity
            .status(ErrorCode.VALIDATION_FAILED.status)
            .body(ErrorResponse(ErrorCode.VALIDATION_FAILED.name, "${exception.parameterName} 파라미터는 필수입니다", request.requestURI))
    }

    @ExceptionHandler(ConstraintViolationException::class)
    fun handleConstraintViolation(
        exception: ConstraintViolationException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        val message = exception.constraintViolations.firstOrNull()?.message
            ?: ErrorCode.VALIDATION_FAILED.message
        return ResponseEntity
            .status(ErrorCode.VALIDATION_FAILED.status)
            .body(ErrorResponse(ErrorCode.VALIDATION_FAILED.name, message, request.requestURI))
    }
}
