import http from 'k6/http';
import { Counter } from 'k6/metrics';

/**
 * W-EXT 램프 — **사람이 보면서 관찰하기 위한** 주입 프로파일.
 *
 * 이산 측정(w-ext.js)과 목적이 다르다. 이산 측정은 평탄 구간의 통계를 깨끗하게 얻는 것이고,
 * 이 램프는 **천장이 생기는 과정**을 시간축에서 보이게 하는 것이다.
 * 그래서 천장(= 스레드 상한 ÷ 지연) 아래 → 천장 근처 → 천장의 2배로 올리며 각 구간을 유지한다.
 *
 * Grafana 에서 보게 되는 것:
 *   ① 천장 아래  — 주입률과 처리량 두 선이 겹쳐 간다. 스레드 사용량이 주입률에 비례해 오른다.
 *   ② 천장 근처  — 스레드 사용량이 상한에 닿는다. p95 가 먼저 들썩인다.
 *   ③ 천장 위    — 두 선이 벌어진다. 처리량은 평평하고 버려진 요청이 쌓이고 p95 가 폭증한다.
 *                 **그 동안 CPU 는 한가하다** — 이게 이 측정의 요점이다.
 *
 * 사용: tools/loadtest/watch.sh  (직접 돌리려면 아래 env 를 채울 것)
 */

const DELAY_MS = Number(__ENV.DELAY_MS || 500);
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// 천장 = 스레드 상한 ÷ 지연. 램프의 각 단은 이 값을 기준으로 정한다 —
// 스레드 수를 바꿔 돌릴 때도 같은 모양의 그래프가 나오게 하려면 절대값을 박아선 안 된다.
const CEILING = Number(__ENV.CEILING || 400);

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: Math.round(CEILING * 0.1),
      timeUnit: '1s',
      // 포화 구간에서 지연이 늘면 같은 주입률을 유지하는 데 VU 가 더 필요하다.
      // 부족하면 k6 가 dropped_iterations 로 기록하는데, 그것도 신호이긴 하나
      // "서버가 못 받은 것"과 "생성기가 못 보낸 것"이 섞이면 해석이 흐려진다. 넉넉히 확보한다.
      preAllocatedVUs: Math.max(200, Math.round(CEILING * 0.8)),
      maxVUs: 3000,
      stages: [
        { duration: '30s', target: Math.round(CEILING * 0.5) },  // ① 천장 아래
        { duration: '45s', target: Math.round(CEILING * 0.5) },
        { duration: '30s', target: CEILING },                    // ② 천장 근처
        { duration: '45s', target: CEILING },
        { duration: '30s', target: CEILING * 2 },                // ③ 천장의 2배 — 과주입
        { duration: '60s', target: CEILING * 2 },
        { duration: '20s', target: 0 },
      ],
      gracefulStop: '15s',
    },
  },
};

const upstreamErrors = new Counter('upstream_errors');

export default function () {
  const res = http.get(`${BASE_URL}/loadtest/ext?delayMs=${DELAY_MS}`, { timeout: '15s' });
  if (res.status !== 200) upstreamErrors.add(1, { status: String(res.status) });
}
