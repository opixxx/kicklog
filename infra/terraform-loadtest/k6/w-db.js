import http from 'k6/http';
import { Counter, Trend } from 'k6/metrics';
import exec from 'k6/execution';

/**
 * W-DB — DB 바운드 워크로드 (외부 HTTP 미접촉).
 *
 * 타깃: `GET /users/me/seasons/{year}` — ADR-0014 의 시즌 집계.
 * 요청당 쿼리 4회 = 집계 3회(경기·쿼터·월별) + 탈퇴 가드 1회(DeletedUserGuardFilter 의 PK 조회).
 *
 * 구속 자원 가설: **HikariCP 커넥션 풀**(기본 10).
 * 처리량 = 풀 크기 ÷ 커넥션 점유 시간 이므로, 스레드를 아무리 늘려도 이 천장은 움직이지 않는다.
 * ADR-0011 이 같은 방식으로 356 req/s 천장을 풀 10 에 귀속시켰다
 * (DatabaseConnections 가 전 구간 정확히 10.0 에 고정).
 *
 * **이 워크로드가 H2 의 반증 장치다**: 가상 스레드가 W-EXT 를 개선하고 W-DB 를 개선하지 못하면,
 * "가상 스레드는 스레드가 천장일 때만 유효하다"가 측정으로 확인된다.
 * 둘 다 개선되면 천장이 스레드였다는 해석 자체가 틀린 것이므로 모델을 고쳐야 한다.
 *
 * 사용: RATE=300 DURATION=30s k6 run w-db.js
 */

const RATE = Number(__ENV.RATE || 200);
const DURATION = __ENV.DURATION || '30s';
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const YEAR = __ENV.YEAR || '2026';
const SUMMARY_PATH = __ENV.SUMMARY_PATH || '';

// 시드 규모 — 집계가 실제로 행을 훑도록 사용자당 경기를 충분히 둔다.
// 빈 테이블이면 쿼리가 인덱스만 보고 끝나 커넥션 점유 시간이 비현실적으로 짧아진다.
const SEED_USERS = Number(__ENV.SEED_USERS || 200);
const SEED_MATCHES_PER_USER = Number(__ENV.SEED_MATCHES_PER_USER || 60);

// 집계 쿼리는 200ms 를 넘지 않을 것으로 보되, 포화 시 큐 대기를 감안해 넉넉히 잡는다.
const preAllocatedVUs = Math.max(50, Math.ceil(RATE * 0.5));
const maxVUs = Math.min(6000, Math.max(preAllocatedVUs * 4, 300));

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    wdb: {
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

const authErrors = new Counter('auth_errors');
/**
 * 워크로드 전용 지연 — `setup()` 의 시드·토큰 요청을 **제외**한다.
 *
 * k6 의 `http_req_duration` 은 setup 요청까지 합산한다. setup 에서 토큰 100건을 받으면
 * 그 빠른 응답들이 분포를 끌어내려 p50 이 실제 워크로드와 무관한 값이 된다
 * (실측: p50 3.5ms vs p95 394ms 로 분포가 두 덩어리로 갈렸다).
 * 그래서 측정 대상 요청만 따로 적재하고, 러너는 이 메트릭을 우선 사용한다.
 */
const workloadDuration = new Trend('workload_duration', true);


/**
 * 시드 + 토큰 발급. setup 은 1회만 돌고 반환값이 모든 VU 에 복제된다.
 *
 * 시드를 매번 하지 않으려면 `SKIP_SEED=true` 로 건너뛴다 — 같은 DB 상태에서
 * 설정만 바꿔 반복 측정할 때 필요하다(시드가 달라지면 쿼리 비용이 달라져 비교가 깨진다).
 */
export function setup() {
      // discardResponseBodies 가 setup 에도 적용되므로 본문을 쓰는 요청은
      // responseType:'text' 로 개별 예외를 준다 (이 한 줄이 없으면 res.body 가 null).
  let from = Number(__ENV.SEEDED_USER_ID_FROM || 0);
  let to = Number(__ENV.SEEDED_USER_ID_TO || 0);

  if (__ENV.SKIP_SEED !== 'true') {
    const res = http.post(
      `${BASE_URL}/loadtest/seed`,
      JSON.stringify({
        userCount: SEED_USERS,
        matchesPerUser: SEED_MATCHES_PER_USER,
        quartersPerMatch: 4,
      }),
      {
        headers: { 'content-type': 'application/json' },
        timeout: '600s',
        responseType: 'text',
      },
    );
    if (res.status !== 200) {
      throw new Error(`시드 실패: HTTP ${res.status} ${res.body}`);
    }
    const body = JSON.parse(res.body);
    from = body.seededUserIdFrom;
    to = body.seededUserIdTo;
    console.log(`[w-db] 시드 완료 — users ${from}~${to}, matches ${body.matchesCreated}`);
  }

  if (!from || !to) {
    throw new Error('시드 사용자 id 범위를 알 수 없습니다 (SKIP_SEED 시 SEEDED_USER_ID_FROM/TO 필요)');
  }

  // 토큰을 미리 받아둔다. 측정 중 토큰 발급 요청이 섞이면 그것도 부하가 된다.
  const tokens = [];
  const sampleCount = Math.min(to - from + 1, 100);
  for (let i = 0; i < sampleCount; i += 1) {
    const userId = from + i;
    const res = http.get(`${BASE_URL}/loadtest/token?userId=${userId}`, { responseType: 'text' });
    if (res.status !== 200) throw new Error(`토큰 발급 실패 userId=${userId}: HTTP ${res.status}`);
    tokens.push(JSON.parse(res.body).accessToken);
  }
  console.log(`[w-db] 토큰 ${tokens.length}개 준비`);
  return { tokens };
}

export default function (data) {
  // VU·반복마다 다른 사용자를 쓴다. 한 사용자만 때리면 같은 행을 반복 조회해
  // Postgres shared_buffers 와 JIT 가 비현실적으로 유리해진다.
  const token = data.tokens[exec.scenario.iterationInTest % data.tokens.length];
  const res = http.get(`${BASE_URL}/users/me/seasons/${YEAR}`, {
    headers: { authorization: `Bearer ${token}` },
    timeout: '15s',
  });
  workloadDuration.add(res.timings.duration);
  if (res.status !== 200) authErrors.add(1, { status: String(res.status) });
}

export function handleSummary(data) {
  const out = {};
  if (SUMMARY_PATH) out[SUMMARY_PATH] = JSON.stringify(data, null, 2);
  return out;
}
