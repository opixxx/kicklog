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
