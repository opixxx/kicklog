plugins {
	kotlin("jvm") version "2.2.21"
	kotlin("plugin.spring") version "2.2.21"
	id("org.springframework.boot") version "4.0.6"
	id("io.spring.dependency-management") version "1.1.7"
	kotlin("plugin.jpa") version "2.2.21"
}

group = "com.opixxx"
version = "0.0.1-SNAPSHOT"
description = "KickLog backend"

java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(17)
	}
}

repositories {
	mavenCentral()
}

dependencies {
	implementation("org.springframework.boot:spring-boot-starter-actuator")
	// 부하테스트 관측 — actuator 지표를 Prometheus 포맷으로 노출한다 (Grafana 실시간 관찰용).
	// loadtest profile 에서만 엔드포인트를 열며(application-loadtest.yml), 운영은 health·info 만 유지한다.
	runtimeOnly("io.micrometer:micrometer-registry-prometheus")
	// 에러 트래킹 — 5xx·미처리 예외를 Sentry 로 전송 (DSN 미설정 시 자동 비활성).
	// starter(autoconfiguration)는 Spring Boot 4 미지원(RestClientCustomizer 제거)이라 코어만 사용 + 수동 init.
	implementation("io.sentry:sentry:8.16.0")
	implementation("org.springframework.boot:spring-boot-starter-data-jpa")
	implementation("org.springframework.boot:spring-boot-starter-flyway")
	implementation("org.springframework.boot:spring-boot-starter-security")
	implementation("org.springframework.boot:spring-boot-starter-validation")
	implementation("org.springframework.boot:spring-boot-starter-webmvc")
	implementation("org.springframework.boot:spring-boot-configuration-processor")
	implementation("org.flywaydb:flyway-database-postgresql")
	implementation("org.jetbrains.kotlin:kotlin-reflect")
	implementation("tools.jackson.module:jackson-module-kotlin")
	runtimeOnly("org.postgresql:postgresql")
	testImplementation("org.springframework.boot:spring-boot-starter-actuator-test")
	testImplementation("org.springframework.boot:spring-boot-starter-data-jpa-test")
	testImplementation("org.springframework.boot:spring-boot-starter-flyway-test")
	testImplementation("org.springframework.boot:spring-boot-starter-security-test")
	testImplementation("org.springframework.boot:spring-boot-starter-validation-test")
	testImplementation("org.springframework.boot:spring-boot-starter-webmvc-test")
	testImplementation("org.jetbrains.kotlin:kotlin-test-junit5")
	testImplementation("org.testcontainers:junit-jupiter:1.20.4")
	testImplementation("org.testcontainers:postgresql:1.20.4")
	testRuntimeOnly("com.h2database:h2")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

kotlin {
	compilerOptions {
		freeCompilerArgs.addAll("-Xjsr305=strict", "-Xannotation-default-target=param-property")
	}
}

allOpen {
	annotation("jakarta.persistence.Entity")
	annotation("jakarta.persistence.MappedSuperclass")
	annotation("jakarta.persistence.Embeddable")
}

tasks.withType<Test> {
	useJUnitPlatform()

	// Testcontainers 는 DOCKER_HOST 가 없으면 기본 소켓(/var/run/docker.sock)만 찾는다.
	// colima·Rancher Desktop 처럼 소켓을 사용자 홈에 두는 런타임에서는 "Docker 없음"으로 판정해
	// @Testcontainers(disabledWithoutDocker = true) 테스트가 **조용히 스킵된다** —
	// 빌드는 SUCCESSFUL 인데 아무것도 검증하지 않는, 가장 발견하기 어려운 실패 상태다.
	// 이미 지정돼 있으면 존중하고, 없을 때만 발견한 소켓을 주입한다.
	if (System.getenv("DOCKER_HOST") == null) {
		val home = System.getProperty("user.home")
		listOf(
			"$home/.colima/default/docker.sock",
			"$home/.rd/docker.sock",
			"$home/.docker/run/docker.sock",
		).firstOrNull { File(it).exists() }?.let { socket ->
			environment("DOCKER_HOST", "unix://$socket")
			// 컨테이너가 호스트 소켓을 마운트할 때 쓰는 경로는 표준 위치로 알려준다.
			environment("TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE", "/var/run/docker.sock")
		}
	}
}
