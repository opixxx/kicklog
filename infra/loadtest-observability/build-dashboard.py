#!/usr/bin/env python3
"""Grafana 대시보드 JSON 생성기.

500 줄짜리 JSON 을 손으로 고치면 패널 하나 바꿀 때마다 id·좌표가 어긋난다.
패널 목록을 코드로 두고 좌표와 id 를 계산하게 해, 대시보드를 리뷰 가능한 형태로 유지한다.

핵심 설계: **밖에서 본 결과(k6)와 서버 안의 자원(백엔드)을 같은 타임라인에 놓는다.**
처리량이 꺾인 순간 어떤 자원이 꽉 찼고 그때 CPU 는 한가했는지를 한 화면에서 봐야
"천장은 하드웨어가 아니라 설정"이라는 판단이 눈으로 확인된다. 따로 보면 인과를 못 본다.

실행: python3 infra/loadtest-observability/build-dashboard.py
      (Grafana 가 10초마다 파일을 다시 읽으므로 재기동 불필요)
"""

import json
import pathlib

DS = {"type": "prometheus", "uid": "kicklog-prom"}

# scrape_interval 2s 에 샘플 5개. 노이즈와 반응성의 균형점이다 —
# 더 짧으면 톱니가 생기고, 더 길면 평탄화 시점이 뭉개진다.
WINDOW = "10s"

# 구성 필터. k6 지표에도 같은 라벨을 붙이므로(--tag config=...) 양쪽에 똑같이 적용한다.
# 한쪽만 걸면 회차가 겹칠 때 "처리량은 A 구성, 스레드는 B 구성"인 그래프가 나온다.
CFG = '{config=~"$config"}'

def dropped(window=None):
    """버려진 요청의 초당 비율.

    drop 이 한 번도 없으면 k6 는 그 시리즈를 아예 보내지 않는다. PromQL 에서 빈 벡터와의
    덧셈은 결과가 빈 벡터이므로, 보정 없이 더하면 **drop 이 0 인 구간에서 주입률 선이 사라진다.**
    `or vector(0)` 으로 "없음"을 0 으로 바꾼다.
    """
    w = window or WINDOW
    return f"(sum(rate(k6_dropped_iterations_total{CFG}[{w}])) or vector(0))"

_next_id = 0


def _id() -> int:
    global _next_id
    _next_id += 1
    return _next_id


def timeseries(title, description, x, y, w, h, targets, unit=None, soft_max=None):
    custom = {
        "lineWidth": 2,
        "fillOpacity": 6,
        "showPoints": "never",
        # 빈 구간을 잇지 않는다. 이으면 "데이터 없음"이 "값이 완만히 변함"으로 보여
        # 스크레이프 실패를 알아차릴 수 없다 — 실제로 그렇게 오독할 뻔했다.
        "spanNulls": False,
        "lineInterpolation": "linear",
        "axisSoftMin": 0,
    }
    if soft_max is not None:
        custom["axisSoftMax"] = soft_max
    defaults = {"custom": custom, "color": {"mode": "palette-classic"}, "min": 0}
    if unit:
        defaults["unit"] = unit
    return {
        "type": "timeseries",
        "id": _id(),
        "title": title,
        "description": description,
        "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {
            "legend": {
                "displayMode": "table",
                "placement": "bottom",
                "showLegend": True,
                "calcs": ["lastNotNull", "max"],
            },
            "tooltip": {"mode": "multi", "sort": "desc"},
        },
        "targets": [
            {
                "refId": chr(65 + i),
                "datasource": DS,
                "expr": expr,
                "legendFormat": legend,
                "editorMode": "code",
                "range": True,
            }
            for i, (expr, legend) in enumerate(targets)
        ],
    }


def stat(title, description, x, y, w, h, expr, unit="none", decimals=0):
    return {
        "type": "stat",
        "id": _id(),
        "title": title,
        "description": description,
        "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {
            "defaults": {
                "unit": unit,
                "decimals": decimals,
                "color": {"mode": "fixed", "fixedColor": "text"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "text", "value": None}]},
            },
            "overrides": [],
        },
        "options": {
            "graphMode": "area",
            "colorMode": "none",
            "textMode": "auto",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        },
        "targets": [
            {"refId": "A", "datasource": DS, "expr": expr, "editorMode": "code", "range": True}
        ],
    }


def row(title, y):
    return {
        "type": "row",
        "id": _id(),
        "title": title,
        "collapsed": False,
        "gridPos": {"x": 0, "y": y, "w": 24, "h": 1},
        "panels": [],
    }


def build():
    panels = []

    # ── 한눈에 ───────────────────────────────────────────────────────────────
    panels.append(row("한눈에", 0))
    panels += [
        stat("처리량", "k6 가 받아낸 초당 요청 수.", 0, 1, 5, 4,
             f"sum(rate(k6_http_reqs_total{CFG}[{WINDOW}]))", "reqps"),
        stat("버려진 요청",
             "주입률을 따라가지 못해 포기된 초당 반복 수. 0 이 아니면 과부하 구간이다.",
             5, 1, 5, 4,
             dropped(), "reqps"),
        stat("p95 응답시간", "주입 지연을 넘는 부분이 전부 큐 대기다.", 10, 1, 4, 4,
             f"max(k6_http_req_duration_p95{CFG})", "ms"),
        stat("Tomcat 스레드 사용",
             "상한에 붙어 평평해지면 그게 천장이다. 가상 스레드에서는 이 지표가 사라진다.",
             14, 1, 5, 4, f"max(tomcat_threads_busy_threads{CFG})"),
        stat("백엔드 CPU",
             "처리량이 꺾였는데 이 값이 낮으면 천장은 하드웨어가 아니다.",
             19, 1, 5, 4, f"max(process_cpu_usage{CFG})", "percentunit", 1),
    ]

    # ── 밖에서 본 결과 ───────────────────────────────────────────────────────
    panels.append(row("밖에서 본 결과 (k6)", 5))
    panels += [
        timeseries(
            "처리량 대 주입률",
            "주입률 = 처리 + 버려진 요청. 두 선이 벌어지기 시작하는 지점이 그 구성의 천장이다.",
            0, 6, 12, 8,
            [
                (f"sum(rate(k6_iterations_total{CFG}[{WINDOW}])) "
                 f"+ {dropped()}", "주입률 (시도)"),
                (f"sum(rate(k6_http_reqs_total{CFG}[{WINDOW}]))", "처리량"),
            ],
            unit="reqps",
        ),
        timeseries(
            "응답시간 분포",
            "꼬리(p99·최대)가 먼저 벌어지고 중앙값이 뒤따라 밀린다. 포화의 초기 신호는 꼬리에 있다.",
            12, 6, 12, 8,
            [
                (f"max(k6_http_req_duration_med{CFG})", "중앙값"),
                (f"max(k6_http_req_duration_p95{CFG})", "p95"),
                (f"max(k6_http_req_duration_p99{CFG})", "p99"),
                (f"max(k6_http_req_duration_max{CFG})", "최대"),
            ],
            unit="ms",
        ),
        timeseries(
            "버려진 요청",
            "open model 이라 서버가 느려져도 주입률은 유지된다 — 못 받아낸 양이 여기 쌓인다. "
            "이 값을 빼고 처리량만 보면 '안정적'으로 오독한다.",
            0, 14, 12, 7,
            [(dropped(), "버려짐/s")],
            unit="reqps",
        ),
        timeseries(
            "k6 가상 사용자",
            "지연이 늘면 같은 주입률을 유지하는 데 더 많은 VU 가 필요해진다. "
            "확보량에 닿으면 생성기 쪽 한계이므로 결과 해석에서 분리해야 한다.",
            12, 14, 12, 7,
            [
                (f"max(k6_vus{CFG})", "사용 중"),
                (f"max(k6_vus_max{CFG})", "확보량"),
            ],
        ),
    ]

    # ── 서버 안에서 ──────────────────────────────────────────────────────────
    panels.append(row("서버 안에서 (백엔드)", 21))
    panels += [
        timeseries(
            "Tomcat 스레드 — 사용 중 대 상한",
            "플랫폼 스레드 모델에서 동시 처리 가능 요청 수의 상한이다. "
            "사용 중이 상한에 붙는 순간이 처리량이 꺾이는 순간과 겹치는지 보라.",
            0, 22, 12, 8,
            [
                (f"max(tomcat_threads_busy_threads{CFG})", "사용 중"),
                (f"max(tomcat_threads_config_max_threads{CFG})", "상한"),
                (f"max(tomcat_threads_current_threads{CFG})", "생성됨"),
            ],
        ),
        timeseries(
            "CPU 사용률",
            "이 패널이 이 측정의 핵심이다. 처리량이 평평한데 CPU 가 낮으면 "
            "서버를 키워도 처리량은 오르지 않는다.",
            12, 22, 12, 8,
            [
                (f"max(process_cpu_usage{CFG})", "백엔드 프로세스"),
                (f"max(system_cpu_usage{CFG})", "호스트 전체"),
            ],
            unit="percentunit", soft_max=1,
        ),
        timeseries(
            "플랫폼 스레드 수",
            "가상 스레드는 여기 집계되지 않는다. 같은 처리량에서 쓰는 OS 스레드 수가 모델을 드러낸다.",
            0, 30, 12, 7,
            [(f"max(jvm_threads_live_threads{CFG})", "살아 있는 스레드")],
        ),
        timeseries(
            "HikariCP 커넥션",
            "대기가 쌓이면 천장이 스레드에서 DB 커넥션 풀로 옮겨간 것이다. "
            "외부 HTTP 워크로드(W-EXT)는 DB 를 타지 않으므로 0 이어야 한다.",
            12, 30, 12, 7,
            [
                (f"max(hikaricp_connections_active{CFG})", "사용 중"),
                (f"max(hikaricp_connections_pending{CFG})", "대기"),
                (f"max(hikaricp_connections_max{CFG})", "풀 크기"),
            ],
        ),
    ]

    return {
        "uid": "kicklog-loadtest",
        "title": "KickLog 부하테스트",
        "description": (
            "k6 가 밖에서 본 결과와 백엔드 안의 자원 상태를 같은 타임라인에 놓는다. "
            "처리량이 꺾이는 순간 어떤 자원이 꽉 찼는지, 그때 CPU 는 한가한지를 한 화면에서 본다."
        ),
        "tags": ["kicklog", "loadtest"],
        "timezone": "browser",
        "editable": True,
        "schemaVersion": 39,
        "refresh": "2s",
        "time": {"from": "now-5m", "to": "now"},
        "timepicker": {"refresh_intervals": ["1s", "2s", "5s", "10s", "30s"]},
        "templating": {
            "list": [
                {
                    "name": "config",
                    "label": "구성",
                    "type": "query",
                    "datasource": DS,
                    "query": {"query": "label_values(jvm_threads_live_threads, config)", "refId": "A"},
                    "refresh": 2,
                    "includeAll": True,
                    "allValue": ".*",
                    "multi": True,
                    "current": {"text": ["All"], "value": ["$__all"]},
                }
            ]
        },
        "panels": panels,
    }


if __name__ == "__main__":
    out = pathlib.Path(__file__).parent / "grafana" / "dashboards" / "kicklog-loadtest.json"
    dashboard = build()
    out.write_text(json.dumps(dashboard, ensure_ascii=False, indent=2) + "\n")
    drawn = [p for p in dashboard["panels"] if p["type"] != "row"]
    print(f"✅ 패널 {len(drawn)}개 → {out}")
    # 스크린샷 스크립트가 참조할 패널 id 를 같이 찍는다 — 번호가 바뀌면 바로 보이도록.
    for p in drawn:
        print(f"   id={p['id']:>2}  {p['title']}")
