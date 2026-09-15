# EXEC_PLAN — jvm-memory-limit

| 항목 | 값 |
|---|---|
| Task | jvm-memory-limit |
| Type | fix |
| Branch | fix/jvm-memory-limit |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/jvm-memory-limit |
| Port | 9000 |
| 생성 시각 | 2026-09-15 13:37 |
| 상태 | `in-progress` |
| 개발 방식 | **런타임 설정 변경 — Kotlin 코드 변경 없음, TDD 비적용** |

---

> **TDD 비적용 사유**: 변경 대상이 `Dockerfile` 의 JVM 옵션과 compose 의 cgroup 제한이다.
> 단위/통합 테스트로 검증 가능한 계층이 아니며, **배포 후 실측**이 유일한 검증 수단이다.
> 3장을 "배포 후 실측 검증"으로 대체한다.

## 1. 목표 (Goal)

2026-09-06 22:25 KST 부터 **9일간 prod 가 마비**된 장애의 근본 원인을 제거한다.

컨테이너에 메모리 제한이 없어 `-XX:MaxRAMPercentage=70` 이 **호스트 전체(917MB)** 를 기준으로
계산됐고, heap 상한이 642MB 로 잡혔다(`MaxHeapSize=673185792` 로 실측 확인).
그 결과 page cache 가 193MB → 22MB 로 고갈되고, 스왑이 없어 OOM killer 대신
**무한 스래싱**에 빠져 nginx·sshd·SSM agent 까지 산 채로 응답 불능이 됐다.

컨테이너 제한을 걸어 (1) heap 상한을 박스 크기에 맞추고, (2) 한계 초과 시
**호스트 마비가 아니라 컨테이너 OOM kill → 자동 재시작**으로 끝나게 한다.

## 2. 접근 (Approach)

### 변경 대상

| 파일 | 변경 |
|---|---|
| `infra/docker-compose.prod.yml` | `mem_limit: 512m` · `memswap_limit: 512m` 추가 |
| `backend/Dockerfile` | `JAVA_OPTS` 를 절대값 기반으로 교체 |

### JAVA_OPTS

```
before: -XX:MaxRAMPercentage=70 -XX:+UseG1GC -Djava.security.egd=...
after : -Xmx224m -XX:MaxMetaspaceSize=160m -XX:+UseG1GC
        -XX:+ExitOnOutOfMemoryError -Djava.security.egd=...
```

- **`MaxRAMPercentage` 제거** — 이 앱은 비-heap 이 226MB 로 커서 퍼센트 방식이면
  제한 크기를 바꿀 때마다 재검산이 필요하다. 절대값이 안전하다.
- **`ExitOnOutOfMemoryError` 추가** — 없으면 OOM 후 스레드만 죽고 프로세스는
  좀비로 남아 `restart: unless-stopped` 가 작동하지 않는다.
- **`MaxMetaspaceSize` 추가** — 기본 무제한. 실측 108MB 에 여유를 둔 160m.

### 메모리 예산 (2026-09-15 복구 직후 실측 기준)

| 항목 | 값 | 근거 |
|---|---|---|
| 물리 메모리 | 916MB | `free -m` |
| 비-JVM 프로세스 | 179MB | `free` used 538MB − java 359MB |
| JVM 비-heap | 226MB | RSS 359MB − heap committed 133MB |
| heap 실사용 | 93MB | `jcmd GC.heap_info` |

→ 컨테이너 512m (비-heap 226 + heap 224 = 450MB, 여유 62MB)
→ 호스트 잔여 page cache **225MB** (정상 운영 시 188MB 였음)

### 양보 불가 규칙

- `memswap_limit` 은 반드시 `mem_limit` 과 **같은 값**. 미지정 시 컨테이너가
  제한만큼 스왑을 추가로 써서 상한이 사실상 2배가 된다.
- heap + 비-heap 이 `mem_limit` 을 넘지 않을 것. 넘으면 정상 트래픽에도 OOM kill.

## 3. 배포 후 실측 검증 (테스트 케이스 대체)

### 기동 직후

- [ ] `docker inspect kicklog-backend | grep -i memory` → `"Memory": 536870912` (0 이 아님)
- [ ] `jcmd 1 VM.flags | grep MaxHeapSize` → `234881024` (224m). **642MB 가 아닐 것**
- [ ] `docker stats --no-stream` → MEM LIMIT 이 `512MiB` 로 표시
- [ ] `curl https://kicklog.org/nginx-health` → 200, `/friendships` → 401

### 24시간 후 (핵심 — 장애 재발 여부)

- [ ] `free -m` → `%memused` 63~70% 대 (장애 직전 83.6%)
- [ ] `free -m` → buff/cache **180MB 이상** (장애 직전 22MB)
- [ ] `sar -r` → `%commit` 165% 이하 (장애 직전 187.3%)
- [ ] 컨테이너 로그에 `Thread starvation` 경고 **0건** (8/21 부터 반복되던 신호)
- [ ] CloudWatch `VolumeReadBytes` → 일 1GB 미만 (장애 시 1243GB/일)

### 회귀 없음 확인

- [ ] 컨테이너 재시작 루프 없음 — `docker ps` 의 STATUS 가 `Up` 유지
- [ ] `docker logs` 에 `OutOfMemoryError` 없음 (있으면 heap 224m 이 부족한 것 → 상향)

## 4. 검증 (Verification)

### 자동 검증

Kotlin 소스 변경이 없어 `./gradlew check` 는 회귀 확인 목적으로만 실행한다.

```bash
cd backend && ./gradlew compileKotlin   # 컴파일 회귀 없음 확인
docker compose -f infra/docker-compose.prod.yml config -q   # compose 문법 검증
```

### 시나리오 검증 (수동)

- iOS 앱 → 시즌 탭 / 친구 탭 정상 로드 (장애 중엔 "알 수 없는 오류")
- 운동 후 라벨링 큐가 즉시 뜨는지 (앱 시작 시 `restoreLabeledMatches` 가 서버 응답 대기)

---

## 위험도 / 롤백

**Risk: Caution**

- heap 224m 이 실사용(93MB)의 2.4배라 여유가 있지만, **트래픽 증가 시 OOM kill 가능성**이 있다.
  발생 시 `docker logs` 에 `OutOfMemoryError` 가 남고 컨테이너가 재시작된다 —
  9일 마비와 달리 **자동 복구되고 로그가 남는다**(이것이 본 변경의 의도).
- 롤백: `.env.deploy` 의 직전 SHA 로 되돌리면 된다 (ADR-0009 D2 자동 롤백 경로).
  단 롤백하면 장애 원인이 그대로 복원되므로, **heap 상향(`-Xmx288m` + `mem_limit 576m`)**
  이 더 나은 대응이다.
- DB 마이그레이션 없음 / API breaking change 없음.

## 후속 / 관련 이슈

본 PR 범위 밖. 별도 작업 필요:

1. **호스트 스왑 1~2GB** — 예측 못한 압박에서 OOM killer 가 정상 발동하게 하는 완충.
   `infra/terraform` user-data 에 넣어야 인스턴스 재생성 시에도 유지된다.
2. **healthcheck → 실제 재시작 연결** — docker healthcheck 는 unhealthy 표시만 하고
   재시작을 트리거하지 않는다. autoheal 또는 systemd watchdog 필요.
3. **앱 레벨 외부 감시** — `StatusCheckFailed` + `CPU >= 90%` 조합(ADR-0009 D3)은
   "OS 는 살았는데 앱만 죽은" 상태를 못 잡는다. 실제 값은 StatusCheck 정상 / CPU 53% 였다.
4. **`SENTRY_DSN` prod 주입** — 기동 로그에 `SENTRY_DSN 미설정` 확인. 장애 내내 꺼져 있었다.
5. **ADR** — free-tier 메모리 예산 정책 (ADR-0009 후속).
6. **iOS 방어** — 앱 시작 시 `restoreLabeledMatches` 가 `await` 로 HealthKit import 를 막고,
   `APIClient` 가 `URLError.timedOut` 을 `.unknown`("알 수 없는 오류")으로 떨어뜨린다.

## 학습 기록

- Trigger: **production-risk**
- Root cause: `MaxRAMPercentage` 는 컨테이너 메모리 제한이 있을 때만 의도대로 동작한다.
  제한이 없으면 호스트 전체가 기준이 되어 heap 상한이 박스를 초과한다.
- Prevention: 컨테이너 JVM 은 `mem_limit` 필수. heap 은 절대값으로, 비-heap 실측 후 산정.
  `ExitOnOutOfMemoryError` 동반. 제한의 본질적 가치는 **"깨끗하게 죽을 수 있게" 하는 것**.
- Promoted to: `docs/agent/learning.md` (2026-09-15 항목, 커밋 예정)
