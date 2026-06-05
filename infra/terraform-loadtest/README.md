# 복제 부하테스트 환경 (terraform-loadtest)

prod 보다 넉넉한 일회성 환경에서 **API 코드/쿼리 병목**을 측정한다. 인프라 천장을 걷어내
순수 애플리케이션 성능을 본다. 끝나면 `destroy`.

> **prod 와 완전 분리**: 이 디렉토리는 prod `infra/terraform/` 와 별개 state(로컬)다.
> prod 리소스를 절대 건드리지 않는다. 반드시 **이 디렉토리 안에서** terraform 을 실행할 것.

## 구성

| 리소스 | 스펙 | 비고 |
|---|---|---|
| backend EC2 | t3.large (2 vCPU / 8 GB) | docker + GHCR pull, loadtest 프로파일, 8080 직접 노출 |
| loadgen EC2 | c5.large | grafana/k6, 같은 VPC(네트워크 변수 제거) |
| RDS | db.t3.medium PostgreSQL 16 | Performance Insights 켬, 일회성(스냅샷·삭제보호 X) |

prod 전용 리소스(Secrets Manager·OIDC·certbot·CD·S3·budget·observability)는 **제외**.

## 사전 준비

1. AWS Console 에서 EC2 key pair 생성 → `ssh_key_name`
2. GHCR PAT(read:packages) 발급 → `ghcr_pat`
3. **loadtest 코드 포함 backend 이미지**가 GHCR 에 있어야 한다 → `backend_image_tag`
   - CD 가 푸시하는 태그는 **full 40자 git SHA** (`sha-<7>` 아님!) 또는 `latest`. main 최신 SHA 사용.
   - 실제 태그 조회(PAT, read:packages): `curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/<owner>/kicklog/tags/list`
   - ⚠️ 잘못된 태그여도 `terraform apply` 는 성공한다(값 미검증). EC2 안 `docker pull` 만 조용히 실패 → 8080 미기동. image/PAT 수정 후엔 `terraform apply -replace=aws_instance.backend` 로 교체(in-place 는 user-data 재실행 안 함).
4. `cp terraform.tfvars.example terraform.tfvars` 후 값 채우기

## 실행

```bash
cd infra/terraform-loadtest
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan      # 생성 리소스 검토 (비용 확인)
terraform apply tfplan          # 실제 생성 (과금 시작)
```

## 부하 측정

```bash
# 1) backend 부팅 확인 (user-data 가 docker pull/run — 1~2분 소요)
curl http://<backend_public_ip>:8080/actuator/health

# 2) 대량 시드 (사용자 1000명, 유저당 매치 300건 → 수십만 행)
curl -X POST http://<backend_public_ip>:8080/loadtest/seed \
  -H 'Content-Type: application/json' \
  -d '{"userCount":1000,"matchesPerUser":300,"quartersPerMatch":4}'

# 3) 토큰 발급(시드된 userId 로)
curl 'http://<backend_public_ip>:8080/loadtest/token?userId=1'

# 4) loadgen 에서 k6 실행 (target 은 backend private IP — 같은 VPC, 네트워크 변수 최소)
#    측정 핫스팟(read): GET /users/me/seasons/{year}(통계 derive), GET /matches(커서 N+1), GET /friendships
scp -i <key.pem> k6/api-load.js ec2-user@<loadgen_public_ip>:~/
ssh -i <key.pem> ec2-user@<loadgen_public_ip>
# ⚠️ sudo 필수(fresh ssh 세션은 docker 그룹 미반영). 스크립트는 /tmp 로(k6 컨테이너 uid 12345 가 홈 700 통과 불가).
cp ~/api-load.js /tmp/ && chmod 644 /tmp/api-load.js
sudo docker run --rm -i -v /tmp:/s \
  -e BASE_URL=http://<backend_private_ip>:8080 \
  -e SEED_USER_FROM=1 -e SEED_USER_TO=1000 \
  grafana/k6 run /s/api-load.js
# HTML(Grafana) 리포트로 보려면: -e K6_WEB_DASHBOARD=true -e K6_WEB_DASHBOARD_EXPORT=/s/k6-report.html
# 종료 후 scp -i <key.pem> ec2-user@<loadgen_public_ip>:/tmp/k6-report.html .
```

> RDS Performance Insights(AWS 콘솔)로 부하 중 느린 쿼리·대기 이벤트를 관찰한다.
> k6 출력의 `http_req_duration{name:seasons|matches_list|friendships}` 태그별 p95 와
> ramping 단계별 처리량 꺾임(knee point)을 함께 본다.

### WRITE(PUT /matches) 측정은 venue 시드 선행 필요
`UpsertMatchRequest.venueId` 가 non-null FK 라, 현재 시드(venue 미생성)로는 write 부하를 걸 수 없다.
`k6/api-load.js` 의 `writeScenario` 는 골격만 두고 비활성화돼 있다 — `LoadTestSeedService` 에 venue 시드를
추가하는 후속 작업 후 활성화한다 (read 시나리오만으로도 핵심 병목인 통계 derive·커서 N+1 은 측정된다).

## 종료 (과금 중단)

```bash
terraform destroy
```

destroy 후 이 디렉토리의 `terraform.tfstate*` 가 비워진다. 비용은 종료된다.
