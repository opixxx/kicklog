package com.opixxx.kicklog.loadtest

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.context.annotation.Profile
import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.web.SecurityFilterChain

/**
 * 부하 테스트 전용 SecurityFilterChain — loadtest 하위 경로만 인증 없이 통과시킨다.
 *
 * 운영 메인 SecurityConfig 를 전혀 건드리지 않기 위해 분리했고, loadtest profile 에서만
 * 활성화된다. 최고 우선순위(HIGHEST_PRECEDENCE)로 loadtest 경로 요청을 먼저 가로채고,
 * 나머지 경로는 기존 메인 체인이 그대로 처리한다.
 */
@Configuration
@Profile("loadtest")
class LoadTestSecurityConfig {

    @Bean
    @Order(Ordered.HIGHEST_PRECEDENCE)
    fun loadTestSecurityFilterChain(http: HttpSecurity): SecurityFilterChain {
        http
            .securityMatcher("/loadtest/**")
            .csrf { it.disable() }
            .authorizeHttpRequests { auth -> auth.anyRequest().permitAll() }
        return http.build()
    }
}
