package com.opixxx.kicklog.loadtest

import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers

/**
 * loadtest MockMvc 테스트용 공유 PostgreSQL 컨테이너 베이스.
 *
 * loadtest/prod 프로파일은 application-test.yml(H2) 을 쓰지 않고 base application.yml 의
 * PostgreSQL 데이터소스 + Flyway validate 를 상속한다. 따라서 실제 Postgres 가 필요하다.
 * 기존 FriendshipMigrationTest 의 Testcontainers 패턴을 그대로 따른다.
 *
 * 컨테이너 미가동(도커 없음) 환경에서는 @Testcontainers(disabledWithoutDocker=true) 로 스킵된다.
 */
@Testcontainers(disabledWithoutDocker = true)
abstract class LoadTestPostgresSupport {

    companion object {
        @Container
        @JvmStatic
        val postgres = PostgreSQLContainer<Nothing>("postgres:16-alpine")

        @DynamicPropertySource
        @JvmStatic
        fun datasource(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url", postgres::getJdbcUrl)
            registry.add("spring.datasource.username", postgres::getUsername)
            registry.add("spring.datasource.password", postgres::getPassword)
            registry.add("spring.datasource.driver-class-name", postgres::getDriverClassName)
            registry.add("spring.flyway.enabled") { "true" }
            registry.add("spring.jpa.hibernate.ddl-auto") { "validate" }
        }
    }
}
