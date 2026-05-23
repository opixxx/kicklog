package com.opixxx.kicklog.common.security

import com.opixxx.kicklog.common.exception.KickLogException
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

    override fun shouldNotFilter(request: HttpServletRequest): Boolean {
        val path = request.requestURI
        return path == "/auth/apple/signin" ||
            path == "/auth/kakao/signin" ||
            path == "/auth/refresh" ||
            path.startsWith("/actuator/")
    }

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val token = request.getHeader("Authorization")
            ?.takeIf { it.startsWith("Bearer ") }
            ?.removePrefix("Bearer ")

        if (token != null) {
            try {
                val claims = jwtTokenProvider.verifyAccessToken(token)
                val principal = KickLogPrincipal(claims.userId)
                SecurityContextHolder.getContext().authentication =
                    UsernamePasswordAuthenticationToken(principal, token, emptyList())
            } catch (exception: KickLogException) {
                SecurityContextHolder.clearContext()
            }
        }

        filterChain.doFilter(request, response)
    }
}
