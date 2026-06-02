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
   - PR #62 merge 후 CD 가 빌드한 `sha-xxxxxxx`, 또는 로컬에서 수동 build/push
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

# 4) loadgen 에서 k6 실행 (target 은 backend private IP — 같은 VPC)
#    k6 스크립트는 scp 로 올리거나 직접 작성. 측정 핫스팟:
#    GET /users/me/seasons/{year}, GET /matches, PUT /matches, GET /friendships
ssh ec2-user@<loadgen_public_ip>
docker run --rm -i -v $PWD:/scripts grafana/k6 run /scripts/scenario.js
```

> RDS Performance Insights(AWS 콘솔)로 부하 중 느린 쿼리·대기 이벤트를 관찰한다.

## 종료 (과금 중단)

```bash
terraform destroy
```

destroy 후 이 디렉토리의 `terraform.tfstate*` 가 비워진다. 비용은 종료된다.
