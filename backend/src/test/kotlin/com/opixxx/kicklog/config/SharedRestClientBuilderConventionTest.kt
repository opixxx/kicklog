package com.opixxx.kicklog.config

import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.extension
import kotlin.io.path.readText
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * 규약 가드 — **외부 HTTP 클라이언트는 공유 `RestClient.Builder` 만 쓴다.**
 *
 * 개별 클라이언트 테스트는 자기가 만든 빌더를 주입하므로, 운영 코드가 `RestClient.create()` 로
 * 되돌아가도 그 테스트들은 그대로 통과한다. 즉 **배선(wiring)은 아무도 지키지 않는다.**
 * 그 빈틈을 메우려고 소스를 직접 훑는다.
 *
 * `RestClient.create()` 는 타임아웃을 설정하지 않고 `HttpURLConnection` 의 기본값은 0(무한)이다.
 * 외부가 거부가 아니라 **응답을 미루면** 호출 스레드가 영구 점유되고, Tomcat 스레드는 전 요청이
 * 공유하므로 로그인 장애가 조회 API 까지 끌고 들어간다 (ADR-0017 D11).
 */
class SharedRestClientBuilderConventionTest {

    @Test
    fun `운영 코드에서 RestClient_create 를 직접 쓰지 않는다`() {
        val sourceRoot = Path.of("src/main/kotlin")
        val sources = Files.walk(sourceRoot).use { paths ->
            paths.filter { it.extension == "kt" }.toList()
        }

        // 경로가 틀리면 스캔 대상이 0건이 되어 **빈 채로 통과**한다 — 가드가 가드를 못 하는 상태다.
        assertTrue(sources.size > 50, "운영 소스를 못 찾았다 (스캔 ${sources.size}건) — 경로를 확인하세요")

        val offenders = sources
            .filter { stripComments(it.readText()).contains("RestClient.create(") }
            .map { sourceRoot.relativize(it).toString() }

        assertTrue(
            offenders.isEmpty(),
            "타임아웃 없는 RestClient.create() 사용 — 공유 restClientBuilder 를 주입받으세요: $offenders",
        )
    }

    @Test
    fun `주석은 걷어내고 실제 호출은 남긴다`() {
        // 가드 자체의 검증. 주석만 제외하다 보면 **진짜 사용까지 놓치는** 방향으로 망가질 수 있는데,
        // 그 경우 위 테스트는 조용히 통과한다. 두 방향을 모두 고정한다.
        val commentedOnly = """
            /** 문서에서 RestClient.create() 를 언급한다. */
            // 줄 주석의 RestClient.create() 도 마찬가지다.
            class Foo(builder: RestClient.Builder) { val c = builder.build() }
        """.trimIndent()
        val realUsage = """
            class Bar {
                private val client = RestClient.create()
            }
        """.trimIndent()

        assertTrue(!stripComments(commentedOnly).contains("RestClient.create("), "주석은 제외돼야 한다")
        assertTrue(stripComments(realUsage).contains("RestClient.create("), "실제 호출은 잡혀야 한다")
    }

    /**
     * 주석을 걷어낸 소스를 돌려준다.
     *
     * 이 규약을 설명하는 KDoc 자체가 `RestClient.create(` 를 언급하므로, 날것으로 훑으면
     * **문서가 위반으로 잡힌다**. Kotlin 블록 주석은 중첩되므로 깊이로 센다.
     *
     * 문자열 리터럴 안의 `//` 는 고려하지 않는다 — 그 경우 줄 뒷부분을 놓쳐 **거짓 음성**이 날 수
     * 있으나, 이 코드베이스에는 해당 사례가 없고 거짓 양성(빌드 실패)보다 조용한 통과가 덜 위험하다.
     */
    private fun stripComments(source: String): String = buildString {
        var blockDepth = 0
        for (line in source.lineSequence()) {
            var index = 0
            while (index < line.length) {
                val rest = line.length - index
                when {
                    blockDepth > 0 && rest >= 2 && line.startsWith("*/", index) -> {
                        blockDepth -= 1; index += 2
                    }
                    rest >= 2 && line.startsWith("/*", index) -> {
                        blockDepth += 1; index += 2
                    }
                    blockDepth > 0 -> index += 1
                    rest >= 2 && line.startsWith("//", index) -> index = line.length
                    else -> {
                        append(line[index]); index += 1
                    }
                }
            }
            append('\n')
        }
    }
}
