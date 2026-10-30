import http from 'k6/http';
import { Counter, Trend } from 'k6/metrics';
import exec from 'k6/execution';

/**
 * W-MIX — 외부 HTTP 와 DB 를 섞은 워크로드.
 *
 * W-EXT·W-DB 를 **따로** 재서 각 자원의 천장을 확정한 뒤에 돈다. 순서가 중요하다:
 * 섞인 상태부터 재면 처리량이 꺾였을 때 범인이 스레드인지 커넥션인지 귀속할 수 없다.
 *
 * 혼합에서 기대되는 결과: 천장은 **먼저 포화하는 쪽**이 정한다.
 * 그리고 외부 호출이 스레드를 길게 점유하면, DB 작업은 커넥션이 남아 있어도
 * 스레드를 못 얻어 굶는다 — 한 자원의 포화가 다른 작업을 끌고 들어가는 전이 현상이다.
 * 이것이 load shedding·bulkhead(후보 ③)의 필요 근거가 된다.
 *
 * 사용: RATE=400 EXT_RATIO=0.5 DURATION=30s k6 run w-mix.js
 */

const RATE = Number(__ENV.RATE || 300);
const DURATION = __ENV.DURATION || '30s';
const DELAY_MS = Number(__ENV.DELAY_MS || 500);
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const YEAR = __ENV.YEAR || '2026';
const EXT_RATIO = Number(__ENV.EXT_RATIO || 0.5);
const SUMMARY_PATH = __ENV.SUMMARY_PATH || '';

const preAllocatedVUs = Math.max(50, Math.ceil((RATE * Math.max(DELAY_MS, 300)) / 1000 * 1.3));
const maxVUs = Math.min(6000, Math.max(preAllocatedVUs * 3, 300));

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    wmix: {
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

// 두 경로를 따로 집계한다. 합쳐 보면 "외부가 DB 를 굶겼다"는 전이 현상이 평균에 묻힌다.
const extErrors = new Counter('ext_errors');
const dbErrors = new Counter('db_errors');
/**
 * 워크로드 전용 지연 — `setup()` 의 시드·토큰 요청을 **제외**한다.
 *
 * k6 의 `http_req_duration` 은 setup 요청까지 합산한다. setup 에서 토큰 100건을 받으면
 * 그 빠른 응답들이 분포를 끌어내려 p50 이 실제 워크로드와 무관한 값이 된다
 * (실측: p50 3.5ms vs p95 394ms 로 분포가 두 덩어리로 갈렸다).
 * 그래서 측정 대상 요청만 따로 적재하고, 러너는 이 메트릭을 우선 사용한다.
 */
const workloadDuration = new Trend('workload_duration', true);


export function setup() {
      // discardResponseBodies 가 setup 에도 적용되므로 본문을 쓰는 요청은
      // responseType:'text' 로 개별 예외를 준다 (이 한 줄이 없으면 res.body 가 null).
  let from = Number(__ENV.SEEDED_USER_ID_FROM || 0);
  let to = Number(__ENV.SEEDED_USER_ID_TO || 0);

  if (__ENV.SKIP_SEED !== 'true') {
    const res = http.post(
      `${BASE_URL}/loadtest/seed`,
      JSON.stringify({
        userCount: Number(__ENV.SEED_USERS || 200),
        matchesPerUser: Number(__ENV.SEED_MATCHES_PER_USER || 60),
        quartersPerMatch: 4,
      }),
      {
        headers: { 'content-type': 'application/json' },
        timeout: '600s',
        responseType: 'text',
      },
    );
    if (res.status !== 200) throw new Error(`시드 실패: HTTP ${res.status} ${res.body}`);
    const body = JSON.parse(res.body);
    from = body.seededUserIdFrom;
    to = body.seededUserIdTo;
  }
  if (!from || !to) throw new Error('시드 사용자 id 범위 불명 (SKIP_SEED 시 SEEDED_USER_ID_FROM/TO 필요)');

  const tokens = [];
  const sampleCount = Math.min(to - from + 1, 100);
  for (let i = 0; i < sampleCount; i += 1) {
    const res = http.get(`${BASE_URL}/loadtest/token?userId=${from + i}`, { responseType: 'text' });
    if (res.status !== 200) throw new Error(`토큰 발급 실패: HTTP ${res.status}`);
    tokens.push(JSON.parse(res.body).accessToken);
  }
  return { tokens };
}

export default function (data) {
  const n = exec.scenario.iterationInTest;
  // 결정적 분배 — 난수로 섞으면 회차 간 비율이 미세하게 달라져 비교가 흔들린다.
  const isExt = (n % 100) < Math.round(EXT_RATIO * 100);

  if (isExt) {
    const res = http.get(`${BASE_URL}/loadtest/ext?delayMs=${DELAY_MS}`, {
      timeout: '15s',
      tags: { path: 'ext' },
    });
    workloadDuration.add(res.timings.duration, { path: 'ext' });
    if (res.status !== 200) extErrors.add(1, { status: String(res.status) });
  } else {
    const token = data.tokens[n % data.tokens.length];
    const res = http.get(`${BASE_URL}/users/me/seasons/${YEAR}`, {
      headers: { authorization: `Bearer ${token}` },
      timeout: '15s',
      tags: { path: 'db' },
    });
    workloadDuration.add(res.timings.duration, { path: 'db' });
    if (res.status !== 200) dbErrors.add(1, { status: String(res.status) });
  }
}

export function handleSummary(data) {
  const out = {};
  if (SUMMARY_PATH) out[SUMMARY_PATH] = JSON.stringify(data, null, 2);
  return out;
}
