package com.opixxx.kicklog.config

import com.opixxx.kicklog.common.security.DeletedUserGuardFilter
import com.opixxx.kicklog.common.security.JwtAuthenticationFilter
import com.opixxx.kicklog.common.security.JwtProperties
import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpStatus
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.HttpStatusEntryPoint
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter

@Configuration
@EnableConfigurationProperties(JwtProperties::class)
class SecurityConfig(
    private val jwtAuthenticationFilter: JwtAuthenticationFilter,
    private val deletedUserGuardFilter: DeletedUserGuardFilter,
) {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        http
            .csrf { it.disable() }
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .authorizeHttpRequests { auth ->
                auth
                    .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                    .requestMatchers("/auth/apple/signin", "/auth/kakao/signin", "/auth/refresh").permitAll()
                    // 부하 테스트 하네스. 핸들러는 loadtest 프로파일에만 등록되므로 prod 에서는
                    // 매핑 자체가 없어 404 가 떨어진다(인증 게이트의 401 보다 404 가 의미상 정확).
                    // permitAll 이어도 prod 에 라우트가 존재하지 않아 노출 위험은 없다.
                    .requestMatchers("/loadtest/**").permitAll()
                    .anyRequest().authenticated()
            }
            .httpBasic { it.disable() }
            .formLogin { it.disable() }
            .exceptionHandling { it.authenticationEntryPoint(HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)) }
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter::class.java)
            .addFilterAfter(deletedUserGuardFilter, JwtAuthenticationFilter::class.java)

        return http.build()
    }
}
