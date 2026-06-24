package com.opixxx.kicklog.common.logging

/**
 * MDC 키 단일 정의 — 키 문자열이 여러 곳에 흩어지면 한 곳만 바꿔도 로그 상관관계가 조용히 깨진다.
 */
object MdcKeys {
    /** 요청별 추적 ID (TraceIdFilter 가 주입, GlobalExceptionHandler·SentryErrorReporter 가 읽음). */
    const val TRACE_ID = "traceId"
}
