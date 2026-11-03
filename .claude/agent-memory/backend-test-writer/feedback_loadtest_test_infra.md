---
name: feedback-loadtest-test-infra
description: 부하테스트 하네스(loadtest 프로파일) 테스트는 Testcontainers 대신 H2 프로파일 겹침 + 실제 JDK HttpServer stub 으로 작성한다
metadata:
  type: feedback
---

DB 를 타지 않는 하네스 경로(W-EXT = `GET /loadtest/ext`)의 테스트에는 **Testcontainers 를 쓰지 않는다.**
대신 `@ActiveProfiles("loadtest", "test")` 처럼 프로파일을 겹쳐 `application-test.yml` 의 H2 를 쓰거나,
`@SpringBootTest(classes = [...], webEnvironment = NONE)` 로 필요한 빈만 올린다.
prod 격리 테스트도 `@ActiveProfiles("prod", "test")` 로 Docker 없이 가능하다
(`@Profile` 빈 필터링은 프로파일 겹침과 무관하다 — 격리 검증 대상은 빈 등록 여부).

외부 의존 stub 은 **실제 HTTP 서버**(`com.sun.net.httpserver.HttpServer`, 포트 0 바인딩)로 띄운다.
`MockRestServiceServer` 금지 — 그쪽은 RestClient 의 request factory 를 갈아끼워서
"어떤 `ClientHttpRequestFactory` 가 주입됐는지"와 커넥션 동작을 검증 불가능하게 만든다.

**Why:** W-EXT 의 설계 전제가 "DB 를 배제해 구속 자원을 Tomcat 스레드로 귀속시킨다"(EXEC_PLAN
2026-10-30 concurrency-ceiling-harness §1)인데, 테스트가 Postgres 를 끌어오면 그 전제를 깨고
Docker 없는 환경에서 전부 skip 된다 (기존 `LoadTestPostgresSupport` 상속 테스트들이 실제로 skip 중).
그리고 측정 대상 자체가 "커넥션 형상"이라 factory 를 모킹하면 검증할 게 남지 않는다.

**How to apply:** `loadtest` 패키지 테스트를 추가할 때 — DB 접촉 여부를 먼저 보고, 미접촉이면
`LoadTestPostgresSupport` 를 상속하지 말 것. 프로퍼티별 형상 비교(simple/pooled)는 프로퍼티만 다른
슬림 컨텍스트 2개로 나누고, 빈 내부 확인이 필요하면 **테스트 쪽 리플렉션**을 쓴다 —
프로덕션 코드의 가시성을 테스트 때문에 넓히지 않는다(사용자 명시 제약).
관련: [[feedback-kotlin-kdoc-nested-comment]]
