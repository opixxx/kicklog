# =============================================
# KickLog Backend — Spring Boot 4 + Kotlin
# =============================================
# Multi-stage build:
#   stage 1: Gradle build → fat jar
#   stage 2: Amazon Corretto 17 runtime (slim) + jar

# ─── Stage 1: Build ───────────────────────────────────
FROM amazoncorretto:17-alpine AS builder
WORKDIR /workspace

# Gradle wrapper + 의존성 정의만 먼저 복사 (캐시 활용)
COPY gradlew gradlew.bat ./
COPY gradle ./gradle
COPY settings.gradle.kts build.gradle.kts ./

# 의존성 미리 다운로드 (소스 변경에도 캐시 재사용)
RUN ./gradlew --no-daemon dependencies --quiet || true

# 소스 복사 + 빌드
COPY src ./src
RUN ./gradlew --no-daemon bootJar -x test

# ─── Stage 2: Runtime ─────────────────────────────────
FROM amazoncorretto:17-alpine AS runtime

# 보안: 비루트 사용자
RUN addgroup -S kicklog && adduser -S kicklog -G kicklog

WORKDIR /app
COPY --from=builder /workspace/build/libs/*.jar app.jar
RUN chown -R kicklog:kicklog /app

USER kicklog

# Spring Boot 헬스 체크용
EXPOSE 8080

# JVM 옵션 (t3.micro 1GB RAM 가정)
#   -XX:MaxRAMPercentage=70  컨테이너 메모리의 70%를 heap으로
#   -XX:+UseG1GC             G1 GC (낮은 지연 시간)
#   -Djava.security.egd      엔트로피 풀 (start-up 빠르게)
ENV JAVA_OPTS="-XX:MaxRAMPercentage=70 -XX:+UseG1GC -Djava.security.egd=file:/dev/./urandom"

# Spring profile (환경변수로 override 가능)
ENV SPRING_PROFILES_ACTIVE=prod

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]

# 헬스체크 (선택 — docker compose에서 정의)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1
