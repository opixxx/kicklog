import http from 'k6/http';
import { Counter } from 'k6/metrics';

/**
 * W-EXT — 외부 HTTP 바운드 워크로드 (DB 미접촉).
 *
 * 구속 자원 가설: **Tomcat 스레드 상한**.
 * 플랫폼 스레드 모델에서 동시 처리 가능 요청 수 = threads.max 이고,
 * 동시성 = 주입률 × 응답시간 이므로 천장은 threads.max ÷ 지연 이다.
 * 지연 200ms · 스레드 200 → 1,000 RPS.
 *
 * **왜 open model(arrival-rate)인가**: closed model(VU 고정)은 서버가 느려지면
 * 주입률도 함께 떨어져 천장이 보이지 않는다. 실제 사용자는 서버가 느려도 계속 오므로
 * 주입률을 고정하고 **처리 못 한 양(dropped_iterations)** 을 측정해야 한다.
 * 이 값을 리포트에서 빼면 처리량이 과대계상된다.
 *
 * 1회 실행 = 1개 주입률. 러너(tools/loadtest/run-measurement.sh)가 주입률을 바꿔 반복한다.
 * 램프 대신 이산 측정을 쓰는 이유는 전이 구간이 평탄 구간 통계에 섞이지 않게 하는 것이다.
 *
 * 사용: RATE=1000 DURATION=30s k6 run w-ext.js
 */

const RATE = Number(__ENV.RATE || 500);
const DURATION = __ENV.DURATION || '30s';
const DELAY_MS = Number(__ENV.DELAY_MS || 200);
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const SUMMARY_PATH = __ENV.SUMMARY_PATH || '';

// 포화 시 지연이 늘어 VU 요구량이 폭증한다. maxVUs 를 넘으면 k6 가 dropped_iterations 로
// 기록하는데, 그것이 바로 "시스템이 주입률을 따라가지 못한다"는 신호다.
const preAllocatedVUs = Math.max(50, Math.ceil((RATE * DELAY_MS) / 1000 * 1.3));
const maxVUs = Math.min(6000, Math.max(preAllocatedVUs * 3, 300));

export const options = {
  discardResponseBodies: true,
  // p99 는 기본 요약에 없다. 과부하 구간의 꼬리 지연이 핵심 지표라 명시적으로 켠다.
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    wext: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs,
      maxVUs,
      gracefulStop: '10s',
    },
  },
};

const upstreamErrors = new Counter('upstream_errors');

export default function () {
  // timeout 을 백엔드 read timeout(10s)보다 길게 둔다. k6 가 먼저 끊으면
  // 백엔드의 동작이 아니라 k6 의 인내심을 측정하게 된다.
  const res = http.get(`${BASE_URL}/loadtest/ext?delayMs=${DELAY_MS}`, { timeout: '15s' });
  if (res.status !== 200) upstreamErrors.add(1, { status: String(res.status) });
}

export function handleSummary(data) {
  const out = {};
  if (SUMMARY_PATH) out[SUMMARY_PATH] = JSON.stringify(data, null, 2);
  return out;
}
