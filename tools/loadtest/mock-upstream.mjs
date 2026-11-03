#!/usr/bin/env node
/**
 * mock 외부 의존 — 지연을 주입할 수 있는 최소 HTTP 서버.
 *
 * 시나리오 1(외부 의존 지연 하의 동시성 처리 모델) 측정에서 Apple JWKS · Kakao 를 대신한다.
 * 실제 외부 API 를 부하 대상으로 삼는 것은 타인의 서비스를 때리는 행위라 불가하고,
 * 지연을 통제할 수 없어 측정값의 분산도 통제할 수 없다.
 *
 * **왜 백엔드와 별도 프로세스인가**: 같은 JVM 안에 지연 엔드포인트를 두면
 * mock 응답을 만드는 작업이 측정 대상인 Tomcat 스레드 풀을 함께 소비한다.
 * 그러면 "스레드 200 이 천장"이라는 가설 자체를 검증할 수 없다 — 구속 자원이 섞인다.
 *
 * **왜 Node 이벤트 루프인가**: 측정 목표가 "클라이언트(백엔드)의 스레드 포화"이므로
 * 서버(mock)는 포화하지 않아야 한다. 요청당 스레드를 쓰지 않는 모델이라
 * 동시 in-flight 수천 건을 타이머로 유지하는 비용이 사실상 없다.
 * mock 이 먼저 포화하면 측정은 무효다 — 그래서 /stats 로 상시 관측한다.
 *
 * 의존 설치 없이 돌아야 한다 (node stdlib 전용).
 *
 * 사용:
 *   node tools/loadtest/mock-upstream.mjs --port 9100 --workers 2
 *   curl 'localhost:9100/delay?ms=200'
 *   curl localhost:9100/stats
 */

import http from 'node:http';
import cluster from 'node:cluster';
import os from 'node:os';
import process from 'node:process';

// ─── 인자 파싱 ───────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const parsed = { port: 9100, workers: 2, defaultDelayMs: 200, maxDelayMs: 10_000 };
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith('--')) continue;
    const value = argv[i + 1];
    switch (key) {
      case '--port': parsed.port = Number(value); i += 1; break;
      case '--workers': parsed.workers = Number(value); i += 1; break;
      case '--default-delay-ms': parsed.defaultDelayMs = Number(value); i += 1; break;
      case '--max-delay-ms': parsed.maxDelayMs = Number(value); i += 1; break;
      default: break;
    }
  }
  return parsed;
}

const options = parseArgs(process.argv.slice(2));

// ─── 통계 ────────────────────────────────────────────────────────────────────
// in-flight 가 곧 "mock 이 동시에 떠안고 있는 요청 수"다. 이 값이 예상(주입률 × 지연)을
// 크게 밑돌면 백엔드가 그만큼 보내지 못하고 있다는 뜻 — 즉 병목이 백엔드에 있다는 신호다.

const stats = {
  inFlight: 0,
  totalRequests: 0,
  peakInFlight: 0,
  startedAt: Date.now(),
};

// ─── 핸들러 ──────────────────────────────────────────────────────────────────

/** 지연 응답 — 요청당 스레드가 아니라 타이머 하나만 쓴다. */
function handleDelay(req, res, url) {
  const raw = url.searchParams.get('ms');
  const requested = raw === null ? options.defaultDelayMs : Number(raw);

  if (!Number.isFinite(requested) || requested < 0 || requested > options.maxDelayMs) {
    res.writeHead(400, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: `ms 는 0~${options.maxDelayMs} 범위여야 합니다` }));
    return;
  }

  stats.inFlight += 1;
  stats.totalRequests += 1;
  if (stats.inFlight > stats.peakInFlight) stats.peakInFlight = stats.inFlight;

  const timer = setTimeout(() => {
    stats.inFlight -= 1;
    // 실제 JWKS 응답과 비슷한 크기를 흉내 낸다 — 직렬화·전송 비용을 0 으로 두면
    // 백엔드의 응답 처리 비용이 과소평가된다.
    const body = JSON.stringify({
      delayedMs: requested,
      pid: process.pid,
      keys: [{ kid: 'mock-kid', kty: 'RSA', alg: 'RS256', n: 'x'.repeat(342), e: 'AQAB' }],
    });
    res.writeHead(200, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) });
    res.end(body);
  }, requested);

  // 클라이언트가 먼저 끊으면(백엔드 타임아웃·스레드 중단) 타이머를 정리한다.
  // 이게 없으면 과부하 구간에서 끊긴 요청의 타이머가 누적돼 mock 이 느려진다.
  res.on('close', () => {
    if (!res.writableEnded) {
      clearTimeout(timer);
      stats.inFlight -= 1;
    }
  });
}

function handleStats(res) {
  const body = JSON.stringify({
    pid: process.pid,
    inFlight: stats.inFlight,
    peakInFlight: stats.peakInFlight,
    totalRequests: stats.totalRequests,
    uptimeSeconds: Math.round((Date.now() - stats.startedAt) / 1000),
  });
  res.writeHead(200, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) });
  res.end(body);
}

function createServer() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    switch (url.pathname) {
      case '/delay': handleDelay(req, res, url); break;
      case '/stats': handleStats(res); break;
      case '/health': res.writeHead(200).end('ok'); break;
      default: res.writeHead(404).end();
    }
  });

  // keep-alive 를 넉넉히 둔다. mock 이 커넥션을 먼저 끊으면 백엔드 쪽에
  // 재연결·TIME_WAIT 이 유발돼 "백엔드의 커넥션 관리 문제"와 구분되지 않는다.
  server.keepAliveTimeout = 120_000;
  server.headersTimeout = 125_000;
  server.requestTimeout = 0;
  server.maxRequestsPerSocket = 0;
  server.listen(options.port, () => {
    console.log(`[mock-upstream] pid=${process.pid} listening on :${options.port}`);
  });
  return server;
}

// ─── 기동 ────────────────────────────────────────────────────────────────────
// 워커 여러 개를 두는 이유는 처리량 여유를 확보하는 것이다. mock 이 측정의 천장이 되면
// 백엔드의 천장을 볼 수 없다 — EXEC_PLAN 의 "목표 주입률 3배 소화" 수용 조건이 이것이다.

const workerCount = Math.max(1, Math.min(options.workers, os.availableParallelism?.() ?? 4));

if (cluster.isPrimary && workerCount > 1) {
  console.log(`[mock-upstream] primary pid=${process.pid} → ${workerCount} workers, port=${options.port}`);
  for (let i = 0; i < workerCount; i += 1) cluster.fork();
  cluster.on('exit', (worker, code) => {
    console.error(`[mock-upstream] worker ${worker.process.pid} 종료 (code=${code}) — 재기동`);
    cluster.fork();
  });
} else {
  createServer();
}
