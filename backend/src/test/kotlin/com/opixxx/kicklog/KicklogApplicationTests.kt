package com.opixxx.kicklog

import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest

@SpringBootTest(
	properties = [
		"spring.datasource.url=jdbc:h2:mem:kicklog;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DEFAULT_NULL_ORDERING=HIGH",
		"spring.datasource.driver-class-name=org.h2.Driver",
		"spring.datasource.username=sa",
		"spring.datasource.password=",
		"spring.jpa.database-platform=org.hibernate.dialect.H2Dialect",
		"spring.jpa.hibernate.ddl-auto=create-drop",
		"spring.flyway.enabled=false",
		"kicklog.jwt.secret=test-secret-test-secret-test-secret-test-secret",
		"kicklog.apple.client-id=com.opixxx.kicklog",
		"kicklog.apple.jwks-url=http://localhost/apple/keys",
		"kicklog.kakao.user-info-url=http://localhost/kakao/user",
	],
)
class KicklogApplicationTests {

	@Test
	fun contextLoads() {
	}

}
