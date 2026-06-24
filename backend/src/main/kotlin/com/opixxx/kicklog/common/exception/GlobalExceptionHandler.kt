package com.opixxx.kicklog.common.exception

import com.opixxx.kicklog.common.logging.MdcKeys
import com.opixxx.kicklog.common.observability.ErrorReporter
import jakarta.servlet.http.HttpServletRequest
import jakarta.validation.ConstraintViolationException
import org.slf4j.LoggerFactory
import org.slf4j.MDC
import org.springframework.http.HttpStatus
import org.springframework.http.HttpStatusCode
import org.springframework.http.ResponseEntity
import org.springframework.web.ErrorResponse as SpringErrorResponse
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
class GlobalExceptionHandler(
    private val errorReporter: ErrorReporter,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(KickLogException::class)
    fun handleKickLogException(
        exception: KickLogException,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        val errorCode = exception.errorCode
        // 5xx 만 Sentry 로 전송 — 4xx 비즈니스 예외(인증·NOT_FOUND·권한 등)는 정상 흐름이라 제외.
        if (errorCode.status.is5xxServerError) {
            logger.error("서버 오류 발생 [{}]", errorCode.name, exception)
            errorReporter.report(exception)
        }
        val message = exception.message ?: errorCode.message
        return errorResponse(errorCode.status, errorCode.name, message, request)
    }

    /**
     * 어떤 핸들러도 처리하지 못한 예외의 최종 안전망.
     *
     * Spring MVC 표준 예외(404 NoResourceFound, 405 MethodNotSupported 등)는 자체 상태코드를 보존한다 —
     * 그러지 않으면 없는 경로 요청까지 500 으로 둔갑해 Sentry 노이즈가 폭증한다.
     * 그 외 진짜 미처리 예외만 표준 ErrorResponse(INTERNAL_ERROR, 500)로 통일하고 Sentry 로 전송한다.
     */
    @ExceptionHandler(Exception::class)
    fun handleUnexpectedException(
        exception: Exception,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        if (exception is SpringErrorResponse) {
            return handleSpringErrorResponse(exception, request)
        }
        logger.error("처리되지 않은 예외 발생", exception)
        errorReporter.report(exception)
        val errorCode = ErrorCode.INTERNAL_ERROR
        return errorResponse(errorCode.status, errorCode.name, errorCode.message, request)
    }

    /** Spring MVC 가 던지는 표준 예외(ErrorResponse 구현)는 상태코드를 보존하고 5xx 만 Sentry 로 보낸다. */
    private fun handleSpringErrorResponse(
        springError: SpringErrorResponse,
        request: HttpServletRequest,
    ): ResponseEntity<ErrorResponse> {
        val status = springError.statusCode
        if (status.is5xxServerError) {
            // Spring 의 ErrorResponse 구현체는 항상 Throwable 이라 안전한 캐스트.
            val throwable = springError as Throwable
            logger.error("서버 오류 발생 (Spring MVC)", throwable)
            errorReporter.report(throwable)
        }
        val code = HttpStatus.resolve(status.value())?.name ?: ErrorCode.INTERNAL_ERROR.name
        val message = springError.body.detail ?: code
        return errorResponse(status, code, message, request)
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
            .body(ErrorResponse(code, message, request.requestURI, traceId = MDC.get(MdcKeys.TRACE_ID)))
    }
}
