// P-steady — 일정 RPS 지속 부하 (Measurement A: TIME_WAIT, B: 처리량 천장)
//
// 60초 미만은 TIME_WAIT 평형 미달로 재현 실패 → DURATION 최소 2분 권장.
// env:
//   RATE     RPS (기본 200)
//   DURATION 지속 시간 (기본 150s)
//   TARGET   대상 URL (기본 http://localhost:8080/loadtest/ping)
import http from 'k6/http';
import { Counter } from 'k6/metrics';

const RATE = parseInt(__ENV.RATE || '200');
const DURATION = __ENV.DURATION || '150s';
const TARGET = __ENV.TARGET || 'http://localhost:8080/loadtest/ping';

const c502 = new Counter('status_502');
const cConnErr = new Counter('conn_errors');

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: Math.max(50, RATE),
      maxVUs: Math.max(200, RATE * 4),
    },
  },
};

export default function () {
  const res = http.get(TARGET);
  if (res.status === 502) c502.add(1);
  if (res.status === 0) cConnErr.add(1); // 커넥션 단계 실패(포트 고갈 등)
}
