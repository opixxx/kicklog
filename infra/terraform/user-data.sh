#!/bin/bash
# EC2 첫 부팅 시 실행되는 셋업 스크립트
# Amazon Linux 2023 기반
set -e

LOG=/var/log/kicklog-userdata.log
exec > >(tee -a "$LOG") 2>&1

echo "===== KickLog EC2 user-data 시작 $(date) ====="

# ─── 시스템 업데이트 ─────────────────────────────────
dnf update -y

# ─── 스왑 2GB (ADR-0013 후속 · 2026-09-06 장애 대책) ──
# t3.micro 의 물리 메모리는 916MB 이고 스왑이 없으면, 메모리가 차는 순간 커널이
# OOM killer 대신 **무한 스래싱**에 빠진다 — page cache 를 버렸다 디스크에서 다시
# 읽기를 반복하며 CPU 와 디스크만 태운다. 프로세스가 죽지 않으므로 restart 정책도
# 작동하지 않는다. 2026-09-06 에 실제로 그렇게 됐고 호스트가 9일간 산 채로 마비됐다.
#
# 스왑은 그 완충이다. 메모리가 부족해지면 스래싱으로 가는 대신 스왑을 쓰다가,
# 그마저 차면 **OOM killer 가 정상 발동**해 프로세스를 죽인다 → 재시작으로 복구된다.
#
# zram 은 이 인스턴스에서 생성되지 않는다:
#   "zram0: system has too much memory (916MB), limit is 800MB, ignoring"
# 따라서 파일 기반 스왑을 직접 만든다.
#
# 주의: 백엔드 컨테이너는 compose 의 memswap_limit=mem_limit 으로 **스왑 사용이 0** 이다.
# 이 스왑은 호스트 프로세스(nginx·docker·containerd·SSM agent·OS) 전용 완충이며,
# 컨테이너는 제한 초과 시 스왑으로 연명하지 않고 즉시 OOM kill → 재시작된다 (의도된 동작).
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# swappiness 10 — 스왑을 최후의 수단으로만 쓴다 (기본 60 은 너무 적극적이라
# 메모리에 여유가 있어도 스왑을 써서 응답 지연을 만든다). 목적은 상시 사용이 아니라
# OOM 직전의 완충이다.
echo 'vm.swappiness=10' > /etc/sysctl.d/99-kicklog-swap.conf
sysctl -w vm.swappiness=10

# ─── 필수 CLI (ADR-0015) ────────────────────────────
# jq: fetch-secrets.sh 가 DB secret JSON 을 파싱한다. 없으면 **첫 배포가 즉시 실패**한다.
#     2026-10-10 점검에서 user-data 에 jq 가 빠져 있는 것이 확인됐다 — 현 박스는
#     수동 설치로 메꿔져 있었고, 그래서 "코드만으로 박스를 재현할 수 없는" 상태였다.
# postgresql16: pg-dump-to-s3.sh 용. 서버가 PostgreSQL 16 이라 15 클라이언트는 덤프를 거부한다.
dnf install -y jq postgresql16

# ─── Docker 설치 ────────────────────────────────────
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

# docker compose plugin (v2)
mkdir -p /usr/local/lib/docker/cli-plugins
curl -sL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ─── nginx 설치 + 기본 설정 ───────────────────────────
dnf install -y nginx
systemctl enable --now nginx

# ⚠️ 여기서 만드는 conf 는 **부팅 직후 임시 placeholder** 다 (HTTP only).
# 운영 conf 의 SoT 는 infra/scripts/nginx-kicklog.conf 이고,
# CD 의 apply-host-config.sh 가 S3 staging 에서 받아 이 파일을 덮어쓴다 (ADR-0015 D3).
# 박스에서 직접 수정하지 말 것 — 다음 배포에 덮어써지고, 저장소와 운영이 갈라진다.
cat > /etc/nginx/conf.d/kicklog.conf <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    # placeholder — apply-host-config.sh 가 TLS(Origin CA) 포함 운영 conf 로 교체한다.
    location = /nginx-health {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "nginx bootstrap\n";
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
nginx -t && systemctl reload nginx

# ─── TLS: Cloudflare Origin CA (certbot 미사용) ───────
# ADR-0015 D1 — Let's Encrypt + certbot --nginx 는 Cloudflare 프록시 뒤에서
# HTTP-01 갱신이 조용히 실패한다 (실제로 인증서가 46일간 만료 상태로 방치됐다).
# 대신 유효기간 15년의 Origin CA 인증서를 SSM 에서 받아 설치한다:
#   infra/scripts/issue-origin-cert.sh (로컬 1회) → install-origin-cert.sh (박스)
# break-glass 로 프록시를 끈 채 ACME 가 필요할 때를 위해 패키지만 남겨둔다.
dnf install -y python3-certbot-nginx

# AASA(Universal Link) · 운영 스크립트 배치 경로 — apply-host-config.sh 가 채운다.
mkdir -p /var/www/kicklog/.well-known /var/www/certbot /opt/kicklog/bin

# ─── Java (선택 — Docker 안에서 실행하면 불필요) ────
# dnf install -y java-17-amazon-corretto-headless

# ─── 작업 디렉토리 ───────────────────────────────────
mkdir -p /opt/kicklog
chown ec2-user:ec2-user /opt/kicklog

# 배포는 사용자가 수동:
#   SSH 접속 후
#   /opt/kicklog/docker-compose.yml 작성
#   docker compose pull && docker compose up -d

echo "===== KickLog EC2 user-data 완료 $(date) ====="
