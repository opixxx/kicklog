"""엣지 헬스 체크 — 외부에서 본 kicklog.org 가 정상인지 5분마다 확인한다.

왜 필요한가 (ADR-0015):
    기존 CloudWatch 알람 6개는 전부 인프라 메트릭(StatusCheck·CPU·FreeStorage·
    DatabaseConnections·VolumeReadBytes)이다. 그래서 "OS 와 DB 는 살아 있는데
    nginx 만 죽은" / "Cloudflare 엣지 장애" / "TLS 가 만료된" 상태를 한 건도
    잡지 못한다. 실제로 오리진 인증서가 46일간 만료된 채 방치됐다.

    이 Lambda 는 VPC 밖에서 실행되어 "사용자가 보는 경로" 를 그대로 호출한다.
    결과를 커스텀 메트릭 1개로 남기고 알람은 그 메트릭을 본다
    (Free Tier: 커스텀 메트릭 10개까지 무료 · Lambda 월 100만 요청 무료).
"""

import os
import time
import urllib.error
import urllib.request

import boto3

NAMESPACE = "KickLog/Edge"
METRIC_NAME = "EdgeHealthy"
TIMEOUT_SECONDS = 10

cloudwatch = boto3.client("cloudwatch")


def _probe(url: str) -> tuple[int, float]:
    """URL 을 호출해 (상태코드, 소요 ms) 를 반환한다. 실패 시 상태코드 0."""
    started = time.monotonic()
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "kicklog-edge-health/1.0"})
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            status = response.status
    except urllib.error.HTTPError as error:
        # 4xx/5xx 도 "응답은 왔다" — 상태코드를 그대로 쓴다 (502/503 이 바로 장애 신호).
        status = error.code
    except Exception:  # 타임아웃·DNS·TLS 실패 등 — 응답 자체가 없는 경우
        status = 0
    return status, (time.monotonic() - started) * 1000


def handler(event, context):  # noqa: ARG001 — EventBridge 스케줄 호출
    url = os.environ["EDGE_HEALTH_URL"]
    status, elapsed_ms = _probe(url)
    healthy = 1 if status == 200 else 0

    cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {"MetricName": METRIC_NAME, "Value": healthy, "Unit": "None"},
            {"MetricName": "EdgeLatencyMs", "Value": elapsed_ms, "Unit": "Milliseconds"},
        ],
    )

    print(f"url={url} status={status} healthy={healthy} elapsed_ms={elapsed_ms:.0f}")
    return {"status": status, "healthy": healthy, "elapsed_ms": round(elapsed_ms)}
