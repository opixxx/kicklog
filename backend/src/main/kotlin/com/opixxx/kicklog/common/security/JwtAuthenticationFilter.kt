package com.opixxx.kicklog.common.security

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter

@Component
class JwtAuthenticationFilter(
    private val jwtTokenProvider: JwtTokenProvider,
) : OncePerRequestFilter() {
    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val token = request.extractBearerToken()
        if (token != null) authenticate(token)
        filterChain.doFilter(request, response)
    }

    private fun authenticate(token: String) {
        runCatching {
            val parsed = jwtTokenProvider.verify(token)
            if (parsed.type == JwtTokenProvider.ACCESS_TYPE) {
                val principal = KickLogPrincipal(parsed.subject.toLong())
                val authentication = UsernamePasswordAuthenticationToken(principal, null, emptyList())
                SecurityContextHolder.getContext().authentication = authentication
            }
        }
    }

    private fun HttpServletRequest.extractBearerToken(): String? {
        val header = getHeader("Authorization") ?: return null
        return header.takeIf { it.startsWith(BEARER_PREFIX) }?.removePrefix(BEARER_PREFIX)
    }

    companion object {
        private const val BEARER_PREFIX = "Bearer "
    }
}
