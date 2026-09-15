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

# JVM 옵션 (t3.micro 1GB RAM · compose 의 mem_limit 512m 전제)
#
# heap 은 절대값으로 고정한다. MaxRAMPercentage 는 컨테이너 메모리 제한이 있을 때만
# 의도대로 동작하는데(없으면 호스트 전체가 기준), 이 앱은 비-heap 이 226MB 로 커서
# 퍼센트 방식이면 제한 크기를 바꿀 때마다 재검산이 필요하다. 2026-09-06 장애 참조
# — 제한 부재로 heap 상한이 642MB 로 잡혀 호스트 전체가 스래싱에 빠졌다.
#
#   -Xmx224m                    heap 상한. 실측 사용량 93MB 의 2.4배
#   -XX:MaxMetaspaceSize=160m   metaspace 상한. 실측 108MB (기본은 무제한)
#   -XX:+UseG1GC                G1 GC (낮은 지연 시간)
#   -XX:+ExitOnOutOfMemoryError OOM 시 즉시 종료 → restart 정책이 재시작하게.
#                               없으면 스레드만 죽고 프로세스는 좀비로 남는다
#   -Djava.security.egd         엔트로피 풀 (start-up 빠르게)
ENV JAVA_OPTS="-Xmx224m -XX:MaxMetaspaceSize=160m -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

# Spring profile (환경변수로 override 가능)
ENV SPRING_PROFILES_ACTIVE=prod

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]

# 헬스체크 (선택 — docker compose에서 정의)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1
