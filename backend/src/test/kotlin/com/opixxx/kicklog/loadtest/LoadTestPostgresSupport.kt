package com.opixxx.kicklog.loadtest

import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Testcontainers

/**
 * loadtest MockMvc 테스트용 공유 PostgreSQL 컨테이너 베이스.
 *
 * loadtest/prod 프로파일은 application-test.yml(H2) 을 쓰지 않고 base application.yml 의
 * PostgreSQL 데이터소스 + Flyway validate 를 상속한다. 따라서 실제 Postgres 가 필요하다.
 *
 * **왜 `@Container` 를 쓰지 않는가 — 싱글턴 컨테이너 패턴**
 *
 * `@Container` 가 붙은 static 컨테이너는 **테스트 클래스마다** 시작·종료된다. 그런데 이 필드는
 * 하위 클래스 전체가 공유하는 하나의 static 이라, 먼저 끝난 클래스가 컨테이너를 내려버린다.
 * 한편 Spring 은 설정이 같은 테스트 컨텍스트를 캐시해 재사용하므로, 두 번째 클래스는
 * **이미 죽은 포트가 박힌** 데이터소스를 그대로 물고 `Connection refused` 로 실패한다
 * (2026-10-30 실측: 두 번째 클래스부터 `Connection to localhost:32773 refused`).
 *
 * 그래서 컨테이너를 한 번만 띄우고 JVM 이 끝날 때까지 유지한다. 정리는 Testcontainers 의
 * Ryuk 사이드카가 맡으므로 직접 stop 하지 않는다.
 *
 * `@Testcontainers(disabledWithoutDocker = true)` 는 **Docker 부재 시 스킵** 용도로만 남긴다
 * (관리 대상 `@Container` 가 없으므로 확장이 컨테이너 수명에 관여하지 않는다).
 * 단, 조용한 스킵은 "통과처럼 보이는 미검증"이라 위험하다 — colima·Rancher 처럼 소켓이
 * 표준 경로에 없는 런타임을 위해 `build.gradle.kts` 의 test 태스크가 DOCKER_HOST 를 찾아 넣는다.
 */
@Testcontainers(disabledWithoutDocker = true)
abstract class LoadTestPostgresSupport {

    companion object {
        // 프로퍼티 등록 시점(= 첫 테스트 컨텍스트 생성)에 lazy 하게 한 번 시작된다.
        private val postgres: PostgreSQLContainer<Nothing> =
            PostgreSQLContainer<Nothing>("postgres:16-alpine").apply { start() }

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
