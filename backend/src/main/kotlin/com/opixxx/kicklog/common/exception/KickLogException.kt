package com.opixxx.kicklog.common.exception

open class KickLogException(
    val errorCode: ErrorCode,
    message: String = errorCode.message,
    cause: Throwable? = null,
) : RuntimeException(message, cause)
