// =============================================
// 트랙 C — API 코드/쿼리 성능 부하 시나리오 (k6)
// =============================================
// 복제 환경(terraform-loadtest)에서 실제 비즈니스 API 의 코드/쿼리 병목을 측정한다.
// 인프라 천장은 넉넉한 스펙으로 제거했으므로, knee point(처리량이 꺾이는 지점)에서
// 무엇이 먼저 포화되는지(앱 CPU? DB? 커넥션풀?)를 RDS Performance Insights 와 함께 본다.
//
// 실행 (loadgen EC2 에서):
//   docker run --rm -i -v $PWD:/s \
//     -e BASE_URL=http://<backend_private_ip>:8080 \
//     -e SEED_USER_FROM=1 -e SEED_USER_TO=1000 \
//     grafana/k6 run /s/api-load.js
//
// 사전: /loadtest/seed 로 사용자/매치/쿼터를 먼저 시드해야 한다 (README 참조).

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const USER_FROM = Number(__ENV.SEED_USER_FROM || 1);
const USER_TO = Number(__ENV.SEED_USER_TO || 1000);
const YEAR = Number(__ENV.YEAR || new Date().getFullYear());
const TOKEN_POOL = Number(__ENV.TOKEN_POOL || 200);

const appErrors = new Rate('app_errors');

export const options = {
  scenarios: {
    // read-heavy: arrival rate 를 점진 상승시켜 처리량 천장(knee point)을 탐색한다.
    read_heavy: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 800,
      stages: [
        { target: 50, duration: '1m' },
        { target: 150, duration: '2m' },
        { target: 400, duration: '2m' },
        { target: 800, duration: '2m' }, // 천장 탐색 — 여기서 p95·에러율 급증 지점이 knee
        { target: 0, duration: '30s' },
      ],
      exec: 'readScenario',
    },
  },
  thresholds: {
    'http_req_duration{name:seasons}': ['p(95)<1500'], // 통계 derive — 가장 무거움
    'http_req_duration{name:matches_list}': ['p(95)<800'],
    'http_req_duration{name:friendships}': ['p(95)<500'],
    app_errors: ['rate<0.05'],
  },
};

// 토큰 풀을 미리 발급한다 — /loadtest/token 호출이 측정 본체에 섞이지 않도록 setup 에서만.
export function setup() {
  const tokens = [];
  for (let i = 0; i < TOKEN_POOL; i++) {
    const uid = randomIntBetween(USER_FROM, USER_TO);
    const res = http.get(`${BASE}/loadtest/token?userId=${uid}`);
    if (res.status === 200) {
      tokens.push(res.json('accessToken'));
    }
  }
  if (tokens.length === 0) {
    throw new Error('토큰 발급 실패 — /loadtest/seed 시드 여부와 BASE_URL 을 확인하세요');
  }
  console.log(`토큰 풀 ${tokens.length}개 발급 완료 (userId ${USER_FROM}~${USER_TO})`);
  return { tokens };
}

function authHeaders(data) {
  const token = data.tokens[randomIntBetween(0, data.tokens.length - 1)];
  return { Authorization: `Bearer ${token}` };
}

export function readScenario(data) {
  const headers = authHeaders(data);

  // 1) 통계 derive — 1년치 매치+쿼터를 메모리로 집계 (읽기 최중량, O(N) 병목 후보)
  const seasons = http.get(`${BASE}/users/me/seasons/${YEAR}`, { headers, tags: { name: 'seasons' } });
  check(seasons, { 'seasons 200': (r) => r.status === 200 }) || appErrors.add(1);

  // 2) 매치 목록 — 커서 페이징 (페이지마다 quarters 로드 → N+1 병목 후보)
  const list = http.get(`${BASE}/matches?size=20`, { headers, tags: { name: 'matches_list' } });
  const listOk = check(list, { 'matches 200': (r) => r.status === 200 });
  if (!listOk) appErrors.add(1);

  // 2-1) 다음 페이지 한 번 더 — 커서 동작 + N+1 가중 측정
  if (listOk && list.json('hasNext') === true) {
    const cursor = encodeURIComponent(list.json('nextCursor'));
    const page2 = http.get(`${BASE}/matches?size=20&cursor=${cursor}`, { headers, tags: { name: 'matches_list' } });
    check(page2, { 'matches p2 200': (r) => r.status === 200 }) || appErrors.add(1);
  }

  // 3) 친구 목록 — (user_low OR user_high) 인덱스 분기 + user 배치 조회
  //    친구 시드 0이면 빈 결과지만 쿼리 경로는 그대로 실행된다.
  const friends = http.get(`${BASE}/friendships`, { headers, tags: { name: 'friendships' } });
  check(friends, { 'friendships 200': (r) => r.status === 200 }) || appErrors.add(1);

  sleep(0.3);
}

// ── WRITE 시나리오 (현재 비활성 — venue 시드 선행 필요) ────────────────────────
// PUT /matches/{clientMatchId} 의 UpsertMatchRequest.venueId 는 non-null FK 다.
// 현재 LoadTestSeedService 는 venue 를 만들지 않으므로(matches.venue_id=NULL),
// write 측정을 하려면 (a) 시드에 venue 추가 + (b) 발급 토큰의 userId 별 venueId 매핑이
// 선행돼야 한다 (후속). 활성화 시 options.scenarios 에 아래 executor 를 추가한다:
//   write_heavy: { executor: 'ramping-arrival-rate', exec: 'writeScenario', ... }
/*
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
export function writeScenario(data) {
  const headers = { ...authHeaders(data), 'Content-Type': 'application/json' };
  const body = JSON.stringify({
    venueId: SEEDED_VENUE_ID,            // ← venue 시드 후 주입
    playedAt: new Date().toISOString(),
    goals: 1, assists: 0, opponentGoals: 1, teamGoals: 2,
    totalDistanceM: 6000, maxSpeedKmh: 24.5, sprintCount: 18, avgHeartRate: 150,
    quarters: [{
      quarterNumber: 1, healthKitWorkoutId: uuidv4(),
      startedAt: new Date(Date.now() - 1800000).toISOString(),
      endedAt: new Date().toISOString(),
      durationSeconds: 1500, distanceM: 1500, avgSpeedKmh: 8.0, maxSpeedKmh: 24.5,
      avgHeartRate: 150, maxHeartRate: 185, sprintCount: 5, activeEnergyKcal: 200,
    }],
  });
  const res = http.put(`${BASE}/matches/${uuidv4()}`, body, { headers, tags: { name: 'match_upsert' } });
  check(res, { 'put 2xx': (r) => r.status === 200 || r.status === 201 }) || appErrors.add(1);
}
*/
