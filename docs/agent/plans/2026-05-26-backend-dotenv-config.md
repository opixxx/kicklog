# EXEC_PLAN — backend-dotenv-config

| 항목 | 값 |
|---|---|
| Task | backend-dotenv-config |
| Type | chore |
| Branch | chore/backend-dotenv-config |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/backend-dotenv-config |
| Port | 9000 |
| 생성 시각 | 2026-05-26 23:01 |
| 상태 | `done` |
| 개발 방식 | 설정 변경 (TDD 비대상) |

---

## 1. 목표

로컬 개발 환경의 비밀값(카카오 REST API 키 등)을 `application.yml` 에 직접 노출하지 않고 `backend/.env` 파일로 분리하여 git 추적에서 제외한다. JWT secret · Apple/Kakao OAuth · 외부 API 키 등이 늘어날 운영 단계까지 같은 패턴으로 확장 가능해야 한다.

## 2. 접근

Spring Boot 자체의 `spring.config.import=optional:file:.env[.properties]` 를 사용한다. 외부 라이브러리 의존성 0.

- **변경 파일**:
  - `backend/src/main/resources/application.yml` — `spring.config.import` 한 줄 추가 (4줄)
  - `backend/.env` — 로컬 개발용 (gitignore 됨, L90)
  - `backend/.env.example` — 커밋 대상 템플릿
- **로딩 동작**: 백엔드 시작 시 working dir(`backend/`) 의 `.env` 를 properties 포맷으로 파싱. 없으면 `optional:` 덕분에 조용히 통과. `application.yml` 의 `${VAR:default}` placeholder 가 그대로 동작.
- **우선순위**: OS 환경변수 > `.env` 파일 > application.yml 기본값. 따라서 EC2 운영 시 systemd `EnvironmentFile=/etc/kicklog.env` 또는 SSM 으로 주입한 OS env 가 `.env` 와 충돌 없이 우선됨.

## 3. 테스트 케이스

설정 파일 변경이므로 단위 테스트 비대상. 수동 검증으로 갈음.

## 4. 검증

### 자동
- `cd backend && ./gradlew compileKotlin` — 컴파일 통과
- `cd backend && ./gradlew check` — 기존 테스트 회귀 없음 (test profile 은 `application-test.yml` 의 mock 사용 — 영향 없음)

### 수동
1. `backend/.env` 에 `KAKAO_REST_API_KEY=<실제 키>` 입력
2. `cd backend && ./gradlew bootRun`
3. JWT 토큰 발급 후:
   ```
   curl -s "http://localhost:8080/places/search?q=마포풋살장&lat=37.556&lng=126.923" \
     -H "Authorization: Bearer $TOKEN" | jq
   ```
4. 정상: 카카오 검색 결과 리스트 반환 / 키 미세팅: `EXTERNAL_KAKAO_UNAVAILABLE`

## (Optional) 위험도 / 롤백

Risk = **Safe**. 기존 환경변수 placeholder 는 변경 없음, `.env` 파일은 옵셔널 로딩이므로 빈 상태여도 기존 동작 그대로 유지된다.

## (Optional) 후속

- `docs/adr/` 에 "환경 비밀값 관리" ADR 한 줄 추가 권장 (로컬 .env / EC2 systemd / 운영 SSM 의 3단 전략)
- EC2 배포 시 systemd unit 파일에 `EnvironmentFile=/etc/kicklog.env` 추가
- JWT_SECRET 운영값을 SSM Parameter Store(SecureString) 로 이전
