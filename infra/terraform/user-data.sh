#!/bin/bash
# EC2 첫 부팅 시 실행되는 셋업 스크립트
# Amazon Linux 2023 기반
set -e

LOG=/var/log/kicklog-userdata.log
exec > >(tee -a "$LOG") 2>&1

echo "===== KickLog EC2 user-data 시작 $(date) ====="

# ─── 시스템 업데이트 ─────────────────────────────────
dnf update -y

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

# Spring Boot 백엔드로 reverse proxy (8080 포트 가정)
cat > /etc/nginx/conf.d/kicklog.conf <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    # 정식 출시 시 도메인 + HTTPS 활성화 → certbot --nginx
    # 현재는 HTTP만 (TestFlight 단계)

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

# ─── Certbot 설치 (도메인 등록 후 사용) ───────────────
dnf install -y python3-certbot-nginx

# 사용법 (도메인 등록 후 수동):
#   sudo certbot --nginx -d kicklog.app
#   자동 갱신은 systemd timer로 자동 처리됨

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
