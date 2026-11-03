import http from 'k6/http';
import { Counter } from 'k6/metrics';

/**
 * W-DB-POOL — DB 커넥션 풀이 구속 자원인 워크로드.
 *
 * **이 워크로드는 H2 의 반증 장치다.**
 * H2: "가상 스레드는 스레드가 천장일 때만 유효하고, 커넥션 풀이 천장이면 무효다."
 *
 * W-EXT 와 짝을 이룬다. 같은 기술(가상 스레드)을 두 워크로드에 적용해
 * 한쪽만 개선되면 가설이 확인되고, 양쪽 다 개선되면 "천장이 스레드였다"는 해석 자체가
 * 틀린 것이므로 모델을 고쳐야 한다. 둘 다 안 되면 가상 스레드가 무용하다는 뜻이다.
 *
 * 천장 = 풀 크기 ÷ 커넥션 점유 시간.
 *   풀 10 · 지연 50ms → 200 rps      풀 50 · 지연 50ms → 1,000 rps
 *
 * Tomcat 스레드(200)는 구속 조건이 아니다 — 200 ÷ 0.05 = 4,000 rps 로 풀 천장보다 한참 위다.
 * 그래서 이 워크로드에서 꺾이는 지점은 스레드가 아니라 풀이어야 한다.
 *
 * 인증·시드가 필요 없다(`/loadtest/**` 는 permitAll, 지연만 주입). 그래서 setup 이 없고
 * w-db.js 와 달리 회차 간 DB 상태가 변하지 않아 반복 측정이 깨끗하다.
 *
 * 사용: RATE=200 DURATION=25s DELAY_MS=50 k6 run w-dbpool.js
 */

const RATE = Number(__ENV.RATE || 100);
const DURATION = __ENV.DURATION || '25s';
const DELAY_MS = Number(__ENV.DELAY_MS || 50);
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const SUMMARY_PATH = __ENV.SUMMARY_PATH || '';

// 포화 시 풀 대기가 붙어 응답이 길어지므로 VU 요구량이 늘어난다. 넉넉히 확보한다.
const preAllocatedVUs = Math.max(50, Math.ceil((RATE * Math.max(DELAY_MS, 200)) / 1000 * 1.5));
const maxVUs = Math.min(6000, Math.max(preAllocatedVUs * 4, 400));

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    wdbpool: {
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

const dbErrors = new Counter('db_errors');

export default function () {
  // 백엔드 read timeout 보다 길게 둔다 — k6 가 먼저 끊으면 서버의 동작이 아니라
  // k6 의 인내심을 측정하게 된다.
  const res = http.get(`${BASE_URL}/loadtest/db?delayMs=${DELAY_MS}`, { timeout: '15s' });
  if (res.status !== 200) dbErrors.add(1, { status: String(res.status) });
}

export function handleSummary(data) {
  const out = {};
  if (SUMMARY_PATH) out[SUMMARY_PATH] = JSON.stringify(data, null, 2);
  return out;
}
