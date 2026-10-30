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
 *
 * `/actuator/metrics` 와 `/actuator/prometheus` 도 함께 열어둔다. 메인 체인은 health·info 만
 * permitAll 이라 메트릭 조회가 401 로 막히는데, 포화 시점의 CPU·스레드·커넥션을 동시에 읽지 못하면
 * "천장이 하드웨어인지 설정인지"를 귀속할 수 없다(판정 기준 G6).
 * `/actuator/prometheus` 는 Prometheus 가 주기적으로 긁어 Grafana 로 실시간 관찰하는 경로다 —
 * 스크레이퍼는 자격증명을 들고 오지 않으므로 인증을 걸면 관찰 자체가 불가능하다.
 * 운영에는 이 체인도, prometheus 엔드포인트 노출도 없으므로 메인 체인의 actuator 정책은 그대로다.
 */
@Configuration
@Profile("loadtest")
class LoadTestSecurityConfig {

    @Bean
    @Order(Ordered.HIGHEST_PRECEDENCE)
    fun loadTestSecurityFilterChain(http: HttpSecurity): SecurityFilterChain {
        http
            .securityMatcher("/loadtest/**", "/actuator/metrics/**", "/actuator/prometheus")
            .csrf { it.disable() }
            .authorizeHttpRequests { auth -> auth.anyRequest().permitAll() }
        return http.build()
    }
}
