# Infra

로컬 개발용 인프라.

## PostgreSQL

```bash
docker compose up -d postgres
docker compose ps
docker compose logs -f postgres
docker compose down            # 컨테이너 정리 (볼륨 유지)
docker compose down -v         # 볼륨까지 삭제
```

기본 접속:
- Host: `localhost`
- Port: `5432`
- DB: `kicklog`
- User / Password: `kicklog` / `kicklog`

## 배포 (TBD)

ADR-0006에서 결정 예정. Railway / Fly.io 후보.
