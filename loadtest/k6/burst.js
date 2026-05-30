// P-burst — 간헐 idle-gap 부하 (Measurement C: idle timeout 비대칭 502 race)
//
// 각 VU: 요청 → sleep(2~4s) → 요청 ... 반복.
// sleep 동안 nginx 의 upstream 풀 커넥션이 idle → backend(1s) 만료 → 죽은 커넥션 →
// 다음 요청이 그 커넥션에 떨어지면 502 (race). steady 고RPS 로는 재현 안 됨.
//
// env:
//   VUS      동시 VU 수 (기본 30)
//   DURATION 지속 시간 (기본 180s)
//   GAP_MIN  idle gap 하한 초 (기본 2)
//   GAP_MAX  idle gap 상한 초 (기본 4)
//   TARGET   대상 URL
import http from 'k6/http';
import { sleep } from 'k6';
import { Counter } from 'k6/metrics';

const VUS = parseInt(__ENV.VUS || '30');
const DURATION = __ENV.DURATION || '180s';
const GAP_MIN = parseFloat(__ENV.GAP_MIN || '2');
const GAP_MAX = parseFloat(__ENV.GAP_MAX || '4');
const TARGET = __ENV.TARGET || 'http://localhost:8080/loadtest/ping';

const c502 = new Counter('status_502');
const cTotal = new Counter('requests_total');

export const options = {
  scenarios: {
    burst: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
};

export default function () {
  const res = http.get(TARGET);
  cTotal.add(1);
  if (res.status === 502) c502.add(1); // race signature (nginx 502)
  sleep(GAP_MIN + Math.random() * (GAP_MAX - GAP_MIN));
}
