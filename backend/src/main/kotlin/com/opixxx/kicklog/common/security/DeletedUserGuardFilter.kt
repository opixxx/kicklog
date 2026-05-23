package com.opixxx.kicklog.common.security

import com.opixxx.kicklog.common.exception.ErrorCode
import com.opixxx.kicklog.common.exception.KickLogException
import com.opixxx.kicklog.user.repository.UserStore
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.stereotype.Component
import org.springframework.util.AntPathMatcher
import org.springframework.web.filter.OncePerRequestFilter
import org.springframework.web.servlet.HandlerExceptionResolver

@Component
class DeletedUserGuardFilter(
    private val userStore: UserStore,
    private val handlerExceptionResolver: HandlerExceptionResolver,
) : OncePerRequestFilter() {

    private val pathMatcher = AntPathMatcher()

    override fun shouldNotFilter(request: HttpServletRequest): Boolean {
        val path = request.requestURI
        return ALLOW_DELETED_PATTERNS.any { pathMatcher.match(it, path) }
    }

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val principal = SecurityContextHolder.getContext().authentication?.principal as? KickLogPrincipal
        if (principal == null) {
            filterChain.doFilter(request, response)
            return
        }

        val user = userStore.findById(principal.userId)
        if (user != null && user.isDeleted()) {
            handlerExceptionResolver.resolveException(
                request,
                response,
                null,
                KickLogException(ErrorCode.USER_DELETED),
            )
            return
        }

        filterChain.doFilter(request, response)
    }

    companion object {
        // deleted 사용자도 통과 허용하는 경로 패턴
        private val ALLOW_DELETED_PATTERNS = listOf(
            "/users/me/cancel-deletion",
            "/auth/**",
            "/actuator/**",
        )
    }
}
