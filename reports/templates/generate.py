#!/usr/bin/env python3
"""
RHOAI PoC 보고서 생성기 — TOML -> HTML

사용법:
    python generate.py poc-report.toml.example -o report.html
    python generate.py poc-report.toml.example --overlay variants/01-enterprise.toml -o enterprise.html
    python generate.py poc-report.toml.example --variant dashboard -o dashboard.html

의존성:
    pip install jinja2
    Python 3.11+ (tomllib 내장) 또는 pip install tomli
"""

import argparse
import copy
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

from jinja2 import Environment, BaseLoader


VARIANT_DEFAULTS = {
    "full": ["summary", "architecture", "operators", "wbs", "scenarios",
             "metrics", "exploratory", "requirements", "resolved", "gaps",
             "personas", "conclusion", "screenshots", "production_roadmap",
             "cost_allocation"],
    "enterprise": ["summary", "sla", "architecture", "operators", "wbs",
                   "scenarios", "metrics", "exploratory", "requirements",
                   "resolved", "gaps", "risk_matrix", "personas", "experts",
                   "conclusion", "production_roadmap", "cost_allocation",
                   "revisions"],
    "print": ["summary", "sla", "architecture", "operators", "wbs",
              "scenarios", "metrics", "exploratory", "requirements",
              "resolved", "gaps", "personas", "conclusion",
              "production_roadmap"],
    "dashboard": ["summary", "sla", "metrics", "scenarios",
                  "exploratory", "gaps", "conclusion"],
    "presentation": ["summary", "sla", "architecture", "metrics",
                     "scenarios", "gaps", "personas", "conclusion",
                     "production_roadmap"],
    "technical": ["summary", "sla", "architecture", "operators", "dsc",
                  "ecosystem", "wbs", "scenarios", "metrics", "exploratory",
                  "requirements", "resolved", "gaps", "risk_matrix",
                  "experts", "conclusion", "production_roadmap",
                  "cost_allocation", "screenshots"],
    "operations": ["summary", "sla", "operators", "dsc", "ecosystem",
                   "metrics", "scenarios", "gaps", "production_roadmap",
                   "cost_allocation", "conclusion"],
}

STATUS_BADGE = {
    "pass": ("bp", "PASS"),
    "cond": ("bc", "조건부"),
    "skip": ("bsk", "SKIP"),
    "partial": ("bpt", "부분"),
    "verified": ("bv", "검증"),
    "oos": ("bo", "OOS"),
}

COLOR_MAP = {
    "rh": "var(--rh)", "pass": "var(--pass)",
    "blue": "var(--blue)", "cond": "var(--cond)",
    "part": "var(--part)",
}

TAB_NAMES = {
    "summary": "Summary", "sla": "SLA", "architecture": "아키텍처",
    "operators": "Operator", "dsc": "DSC", "ecosystem": "에코시스템",
    "wbs": "WBS", "scenarios": "시나리오", "metrics": "실측값",
    "exploratory": "Exploratory", "requirements": "전체 85개",
    "resolved": "해소 이력", "gaps": "Gap", "risk_matrix": "리스크",
    "personas": "페르소나", "experts": "전문가", "conclusion": "결론",
    "screenshots": "스크린샷", "production_roadmap": "프로덕션",
    "cost_allocation": "비용", "revisions": "변경이력",
}


def deep_merge(base: dict, overlay: dict) -> dict:
    result = copy.deepcopy(base)
    for key, val in overlay.items():
        if key in result and isinstance(result[key], dict) and isinstance(val, dict):
            result[key] = deep_merge(result[key], val)
        else:
            result[key] = copy.deepcopy(val)
    return result


def load_toml(path: Path) -> dict:
    with open(path, "rb") as f:
        return tomllib.load(f)


def resolve_config(data: dict) -> tuple[str, list[str], str, dict]:
    tmpl = data.get("template", {})
    variant = tmpl.get("variant", "full")
    sections = tmpl.get("sections") or VARIANT_DEFAULTS.get(variant, VARIANT_DEFAULTS["full"])
    theme = tmpl.get("theme", "auto")
    style = data.get("style", {})
    return variant, sections, theme, style


def build_html(data: dict) -> str:
    variant, sections, theme, style = resolve_config(data)

    env = Environment(loader=BaseLoader(), autoescape=False)
    template = env.from_string(HTML_TEMPLATE)
    return template.render(
        d=data,
        variant=variant,
        sections=sections,
        theme=theme,
        style=style,
        SB=STATUS_BADGE,
        CM=COLOR_MAP,
        TN=TAB_NAMES,
    )


# ── HTML 템플릿 ──────────────────────────────────────────
HTML_TEMPLATE = r'''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{{ d.meta.title }} - {{ d.meta.customer }}</title>
{% if variant != 'print' %}
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
{% endif %}
<style>
:root{--rh:#EE0000;--bg:#F5F6FA;--card:#FFF;--tx:#1A1A2E;--tx2:#6B7280;--bd:#E5E7EB;--pass:#10B981;--passbg:#ECFDF5;--cond:#F59E0B;--condbg:#FFFBEB;--skip:#6B7280;--skipbg:#F3F4F6;--part:#8B5CF6;--partbg:#F5F3FF;--blue:#3B82F6;--bluebg:#EFF6FF;--nav:#1E293B;--sh:{{ style.get('card_shadow','0 1px 3px rgba(0,0,0,.06)') }};--accent:{{ style.get('accent_color','#EE0000') }};--radius:{{ style.get('border_radius','14px') }}}
[data-theme="dark"]{--bg:#0F172A;--card:#1E293B;--tx:#E2E8F0;--tx2:#94A3B8;--bd:#334155;--nav:#020617;--passbg:#064E3B;--condbg:#78350F;--skipbg:#1E293B;--partbg:#2E1065;--bluebg:#1E3A5F}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:{{ style.get('font_family',"-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif") }};background:var(--bg);color:var(--tx);line-height:1.6;transition:background .3s,color .3s}
.ct{max-width:{{ style.get('max_width','1200px') }};margin:0 auto;padding:0 24px}
.hd{background:{{ style.get('header_gradient','linear-gradient(135deg,#1A1A2E,#16213E,#0F3460)') }};color:#fff;padding:36px 0 28px;position:relative;overflow:hidden}
.hd::after{content:'';position:absolute;top:0;right:0;width:400px;height:100%;background:linear-gradient(135deg,transparent 40%,rgba(238,0,0,.15))}
.hd-c{position:relative;z-index:1;display:flex;justify-content:space-between;align-items:flex-start}
.hd-l{flex:1}.hd-badge{display:inline-block;background:var(--accent);padding:3px 14px;border-radius:4px;font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;margin-bottom:10px}
.hd h1{font-size:{{ style.get('heading_size','30px') }};font-weight:800;margin-bottom:4px}
.hd h2{font-size:15px;font-weight:400;opacity:.85;margin-bottom:14px}
.hd-m{display:flex;flex-wrap:wrap;gap:18px;font-size:12px;opacity:.75}
.thm{background:rgba(255,255,255,.15);border:none;color:#fff;padding:7px 14px;border-radius:8px;cursor:pointer;font-size:12px;font-weight:500}
.tn{background:var(--nav);position:sticky;top:0;z-index:100;box-shadow:0 2px 8px rgba(0,0,0,.15)}
.tl{display:flex;gap:0;overflow-x:auto;scrollbar-width:none}.tl::-webkit-scrollbar{display:none}
.tb{background:none;border:none;color:rgba(255,255,255,.6);padding:12px 20px;font-size:12px;font-weight:600;cursor:pointer;white-space:nowrap;border-bottom:3px solid transparent;transition:all .2s}
.tb:hover{color:rgba(255,255,255,.9);background:rgba(255,255,255,.05)}.tb.a{color:#fff;border-bottom-color:var(--accent)}
.tp{display:none;padding:{{ style.get('section_padding','36px 0') }};animation:fi .3s ease}.tp.a{display:block}
@keyframes fi{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
.st{font-size:20px;font-weight:700;margin-bottom:6px;display:flex;align-items:center;gap:10px}
.st::before{content:'';width:4px;height:22px;background:var(--accent);border-radius:2px}
.ss{color:var(--tx2);margin-bottom:24px;font-size:13px}
.kg{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;margin-bottom:18px}
.kc{background:var(--card);border-radius:var(--radius);padding:22px 18px;box-shadow:var(--sh);border:1px solid var(--bd);position:relative;overflow:hidden;transition:transform .2s}
.kc:hover{transform:translateY(-2px)}.kc::after{content:'';position:absolute;top:0;left:0;width:100%;height:4px}
.kl{font-size:11px;color:var(--tx2);font-weight:600;text-transform:uppercase;letter-spacing:.5px;margin-bottom:5px}
.kv{font-size:{{ style.get('kpi_value_size','38px') }};font-weight:800;line-height:1}
.ks{font-size:11px;color:var(--tx2);margin-top:5px}
.b{display:inline-block;padding:2px 9px;border-radius:10px;font-size:10px;font-weight:700}
.bp{background:var(--passbg);color:var(--pass)}.bc{background:var(--condbg);color:var(--cond)}
.bsk{background:var(--skipbg);color:var(--skip)}.bpt{background:var(--partbg);color:var(--part)}
.bv{background:var(--bluebg);color:var(--blue)}.bo{background:#FEF3C7;color:#92400E}
.tc{background:var(--card);border-radius:var(--radius);overflow:hidden;box-shadow:var(--sh);border:1px solid var(--bd)}
table{width:100%;border-collapse:collapse}thead{background:var(--bg)}
th{padding:10px 14px;text-align:left;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:var(--tx2);border-bottom:2px solid var(--bd)}
td{padding:10px 14px;font-size:12px;border-bottom:1px solid var(--bd)}tr:last-child td{border-bottom:none}tr:hover{background:rgba(59,130,246,.03)}
.cg{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:20px}
.cc{background:var(--card);border-radius:var(--radius);padding:20px;box-shadow:var(--sh);border:1px solid var(--bd)}.cc h4{font-size:13px;font-weight:700;margin-bottom:14px}
.cw{position:relative;height:{{ style.get('chart_height','240px') }}}
.mg{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}
.mc{background:var(--card);border-radius:10px;padding:16px;box-shadow:var(--sh);border:1px solid var(--bd);text-align:center;transition:transform .2s}
.mc:hover{transform:translateY(-2px)}.mc .ml{font-size:10px;color:var(--tx2);margin-bottom:5px}
.mc .mv{font-size:24px;font-weight:800}.mc .mu{font-size:12px;color:var(--tx2)}.mc .mr{font-size:9px;color:var(--pass);margin-top:2px}
.gg{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}
.gc{background:var(--card);border-radius:10px;padding:18px;border:1px solid var(--bd);border-left:4px solid var(--cond);transition:transform .2s}
.gc:hover{transform:translateY(-2px)}.gc h4{font-size:13px;margin-bottom:5px}
.gc p{font-size:11px;color:var(--tx2);line-height:1.5}
.gt{display:inline-block;font-size:9px;background:#FEF3C7;color:#92400E;padding:2px 7px;border-radius:3px;font-weight:700;margin-bottom:5px}
.cn{background:linear-gradient(135deg,var(--passbg),#F0FDF4);border-radius:var(--radius);padding:24px;border:1px solid #BBF7D0}
[data-theme="dark"] .cn{background:linear-gradient(135deg,#064E3B,#065F46);border-color:#047857}
.cn h3{color:#065F46;margin-bottom:12px;font-size:16px}[data-theme="dark"] .cn h3{color:#6EE7B7}
.cn ul{list-style:none;padding:0}.cn li{padding:5px 0 5px 22px;position:relative;color:#047857;font-size:12px}
[data-theme="dark"] .cn li{color:#A7F3D0}.cn li::before{content:'\2713';position:absolute;left:0;color:var(--pass);font-weight:bold}
.ft2{background:#1A1A2E;color:rgba(255,255,255,.5);padding:20px 0;font-size:11px;text-align:center}
.ar{cursor:pointer}.ar td:first-child::before{content:'\25B6';font-size:8px;margin-right:6px;display:inline-block;transition:transform .2s;color:var(--tx2)}
.ar.o td:first-child::before{transform:rotate(90deg)}.ad{display:none;background:var(--bg)}.ad.o{display:table-row}
.ad td{padding:12px 14px 12px 40px;font-size:12px;color:var(--tx2);line-height:1.6}
.dg{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:6px}
.di{background:var(--card);padding:8px 12px;border-radius:6px;border:1px solid var(--bd)}
.di .dl{font-size:10px;color:var(--tx2);text-transform:uppercase}.di .dv{font-size:14px;font-weight:700;margin-top:1px}
.fb{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:16px}
.sla-pass{color:var(--pass);font-weight:700}.risk-high{color:#EF4444;font-weight:700}.risk-med{color:var(--cond);font-weight:700}.risk-low{color:var(--pass)}
.conf-badge{position:fixed;top:10px;right:10px;background:#EF4444;color:#fff;padding:4px 12px;border-radius:4px;font-size:10px;font-weight:700;z-index:200;opacity:.8}
.insight{background:var(--card);border-radius:var(--radius);padding:20px 24px;border:1px solid var(--bd);margin:20px 0;border-left:4px solid var(--accent)}
.insight h4{font-size:14px;margin-bottom:8px;color:var(--accent)}.insight p{font-size:12px;color:var(--tx2);line-height:1.7}
.insight .tag{font-size:9px;background:var(--accent);color:#fff;padding:2px 8px;border-radius:3px;font-weight:700;margin-bottom:8px;display:inline-block}
{% if variant == 'print' %}
@media print{.tn,.thm,.fb,.sb{display:none!important}.tp{display:block!important;break-inside:avoid}body{background:#fff}.hd{background:#1A1A2E!important}}
@media screen{.tp{display:none}.tp.a{display:block}}
{% endif %}
{% if variant == 'presentation' %}
.tp.a{display:block}.tp>div{width:100%}
.st{font-size:28px}.kv{font-size:56px}.ss{font-size:15px}
{% endif %}
@media(max-width:768px){.cg{grid-template-columns:1fr}.kg{grid-template-columns:1fr 1fr}.hd h1{font-size:22px}.hd-c{flex-direction:column;gap:12px}}
</style>
</head>
<body{% if theme == 'dark' %} data-theme="dark"{% endif %}>
{% if d.template is defined and d.template.get('confidential') %}<div class="conf-badge">{{ d.template.get('classification','CONFIDENTIAL') }}</div>{% endif %}

<div class="hd"><div class="ct hd-c"><div class="hd-l">
<div class="hd-badge">{{ d.meta.badge }}</div>
<h1>{{ d.meta.title }}</h1><h2>{{ d.meta.subtitle }}</h2>
<div class="hd-m"><span>{{ d.meta.poc_period }}</span><span>{{ d.meta.ocp_version }}</span><span>{{ d.meta.gpu_spec }}</span><span>{{ d.meta.rhoai_version }}</span></div>
</div>{% if variant != 'print' %}<button class="thm" onclick="TT()">Dark Mode</button>{% endif %}</div></div>

<div class="tn"><div class="ct"><div class="tl">
{% for sec in sections %}<button class="tb{% if loop.first %} a{% endif %}" onclick="SW('{{ sec }}',this)">{{ TN.get(sec,sec) }}</button>{% endfor %}
</div></div></div>

{# ===== SUMMARY ===== #}
{% if 'summary' in sections %}
<div class="tp{% if sections[0]=='summary' %} a{% endif %}" id="t-summary"><div class="ct">
<div class="st">Executive Summary</div><p class="ss">고객 요구사항에 대한 검증 결과 종합</p>
<div class="kg">
<div class="kc"><div class="kl">전체 커버율</div><div class="kv" style="color:var(--rh)">{{ d.summary.total_coverage_pct }}%</div><div class="ks">{{ d.summary.total_label }}</div></div>
<div class="kc"><div class="kl">시나리오 PASS율</div><div class="kv" style="color:var(--pass)">{{ d.summary.scenario_pass_pct }}%</div><div class="ks">{{ d.summary.scenario_pass_label }}</div></div>
<div class="kc"><div class="kl">검증 완료</div><div class="kv" style="color:var(--blue)">{{ d.summary.verified_count }}</div><div class="ks">{{ d.summary.verified_label }}</div></div>
<div class="kc"><div class="kl">Operator</div><div class="kv" style="color:var(--cond)">{{ d.summary.operator_count }}</div><div class="ks">{{ d.summary.operator_label }}</div></div>
</div>
{% if variant != 'print' %}
<div class="cg">
<div class="cc"><h4>시나리오 검증 현황</h4><div class="cw"><canvas id="c1"></canvas></div></div>
<div class="cc"><h4>전체 커버리지</h4><div class="cw"><canvas id="c2"></canvas></div></div>
</div>
{% endif %}
<div class="tc"><table><thead><tr><th>구분</th><th>항목</th><th>검증</th><th>조건부</th><th>SKIP</th><th>커버율</th></tr></thead><tbody>
{% for row in d.summary.coverage_table %}<tr{% if row.get('bold') %} style="font-weight:700"{% endif %}><td>{{ row.category }}</td><td>{{ row.total }}</td><td>{{ row.verified }}</td><td>{{ row.conditional }}</td><td>{{ row.skip }}</td><td><span class="b {{ SB.get(row.status,('bsk','?'))[0] }}">{{ row.coverage }}</span></td></tr>{% endfor %}
</tbody></table></div>
{% if d.get('persona_insight') and d.persona_insight.get('summary') %}
<div class="insight"><div class="tag">{{ d.persona_insight.summary.get('persona','Expert') }} View</div><h4>{{ d.persona_insight.summary.get('title','') }}</h4><p>{{ d.persona_insight.summary.get('body','') }}</p></div>
{% endif %}
</div></div>
{% endif %}

{# ===== SLA ===== #}
{% if 'sla' in sections and d.summary.get('sla_targets') %}
<div class="tp" id="t-sla"><div class="ct">
<div class="st">SLA/SLO 달성 현황</div><p class="ss">프로덕션 목표 대비 PoC 실측 성과</p>
<div class="tc"><table><thead><tr><th>지표</th><th>목표</th><th>실측</th><th>상태</th><th>여유율</th></tr></thead><tbody>
{% for sla in d.summary.sla_targets %}<tr><td>{{ sla.metric }}</td><td>{{ sla.target }}</td><td><strong>{{ sla.actual }}</strong></td><td><span class="b {{ SB.get(sla.status,('bsk','?'))[0] }}">{{ SB.get(sla.status,('?','?'))[1] }}</span></td><td class="sla-{{ sla.status }}">{{ sla.margin }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== ARCHITECTURE ===== #}
{% if 'architecture' in sections %}
<div class="tp" id="t-architecture"><div class="ct">
<div class="st">클러스터 아키텍처</div><p class="ss">PoC 검증 환경의 인프라 구성</p>
{% if d.get('architecture') %}
<div class="kg">
{% for card in d.architecture.get('kpi_cards',[]) %}<div class="kc"><div class="kl">{{ card.label }}</div><div class="kv" style="color:{{ CM.get(card.color,'var(--tx)') }};font-size:28px">{{ card.value }}</div><div class="ks">{{ card.sub }}</div></div>{% endfor %}
</div>
{% if d.architecture.get('infra') %}
<div class="tc"><table><thead><tr><th>항목</th><th>값</th></tr></thead><tbody>
{% for row in d.architecture.infra %}<tr><td>{{ row.label }}</td><td><code>{{ row.value }}</code></td></tr>{% endfor %}
</tbody></table></div>
{% endif %}
{% if d.architecture.get('servers') %}
<div class="st" style="margin-top:24px;font-size:16px">서버 인프라</div>
<div class="tc" style="margin-top:12px"><table><thead><tr><th>역할</th><th>인스턴스</th><th>수량</th><th>vCPU</th><th>Memory</th><th>GPU</th><th>비고</th></tr></thead><tbody>
{% for srv in d.architecture.servers %}<tr{% if srv.get('highlight') %} style="background:var(--{{ srv.highlight }}bg)"{% endif %}><td>{{ srv.role }}</td><td>{{ srv.instance }}</td><td>{{ srv.count }}</td><td>{{ srv.vcpu }}</td><td>{{ srv.memory }}</td><td>{{ srv.gpu }}</td><td>{{ srv.note }}</td></tr>{% endfor %}
</tbody></table></div>
{% endif %}
{% endif %}
</div></div>
{% endif %}

{# ===== METRICS ===== #}
{% if 'metrics' in sections %}
<div class="tp" id="t-metrics"><div class="ct">
<div class="st">주요 실측값</div><p class="ss">핵심 성능 지표</p>
<div class="mg">
{% for m in d.metrics %}<div class="mc"><div class="ml">{{ m.label }}</div><div class="mv" style="color:{{ CM.get(m.color,'var(--tx)') }}">{{ m.value }}<span class="mu">{{ m.unit }}</span></div><div class="mr">{{ m.threshold }}</div></div>{% endfor %}
</div>
{% if d.get('persona_insight') and d.persona_insight.get('metrics') %}
<div class="insight"><div class="tag">{{ d.persona_insight.metrics.get('persona','Expert') }} View</div><h4>{{ d.persona_insight.metrics.get('title','') }}</h4><p>{{ d.persona_insight.metrics.get('body','') }}</p></div>
{% endif %}
</div></div>
{% endif %}

{# ===== SCENARIOS ===== #}
{% if 'scenarios' in sections %}
<div class="tp" id="t-scenarios"><div class="ct">
<div class="st">시나리오별 검증 결과</div><p class="ss">S1~S6 핵심 시나리오 (클릭하여 상세 펼치기)</p>
<div class="tc"><table><thead><tr><th>No</th><th>시나리오</th><th>항목</th><th>상태</th><th>비고</th></tr></thead><tbody>
{% for s in d.scenarios %}
<tr class="ar" onclick="TA(this)"><td>{{ s.no }}</td><td>{{ s.scenario }}</td><td>{{ s.item }}</td><td><span class="b {{ SB.get(s.status,('bsk','?'))[0] }}">{{ SB.get(s.status,('?','?'))[1] }}</span></td><td>{{ s.note }}</td></tr>
<tr class="ad"><td colspan="5">{% if s.get('details') %}<div class="dg">{% for dd in s.details %}<div class="di"><div class="dl">{{ dd.label }}</div><div class="dv"{% if dd.get('color') %} style="color:{{ CM.get(dd.color,'') }}"{% endif %}>{{ dd.value }}</div></div>{% endfor %}</div>{% elif s.get('details_text') %}{{ s.details_text }}{% endif %}</td></tr>
{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== EXPLORATORY ===== #}
{% if 'exploratory' in sections %}
<div class="tp" id="t-exploratory"><div class="ct">
<div class="st">Exploratory 검증</div><p class="ss">시나리오 미배정 항목 검증 결과</p>
<div class="tc"><table><thead><tr><th>No</th><th>항목</th><th>상태</th><th>실측 요약</th></tr></thead><tbody>
{% for e in d.exploratory %}<tr><td>{{ e.no }}</td><td>{{ e.item }}</td><td><span class="b {{ SB.get(e.status,('bsk','?'))[0] }}">{{ SB.get(e.status,('?','?'))[1] }}</span></td><td>{{ e.summary }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== OPERATORS ===== #}
{% if 'operators' in sections %}
<div class="tp" id="t-operators"><div class="ct">
<div class="st">설치된 Operator 목록</div><p class="ss">PoC 클러스터에 설치된 전체 Operator</p>
<div class="tc"><table><thead><tr><th>Layer</th><th>Operator</th><th>버전</th><th>채널</th><th>의존</th><th>역할</th></tr></thead><tbody>
{% for op in d.operators %}<tr{% if op.get('highlight') %} style="background:var(--{{ op.highlight }}bg)"{% endif %}><td>{{ op.layer }}</td><td><strong>{{ op.name }}</strong></td><td>{{ op.version }}</td><td>{{ op.channel }}</td><td>{{ op.depends }}</td><td>{{ op.role }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== DSC ===== #}
{% if 'dsc' in sections and d.get('dsc_components') %}
<div class="tp" id="t-dsc"><div class="ct">
<div class="st">RHOAI 컴포넌트 (DSC)</div><p class="ss">DataScienceCluster default-dsc Ready=True</p>
<div class="tc"><table><thead><tr><th>컴포넌트</th><th>상태</th><th>용도</th></tr></thead><tbody>
{% for c in d.dsc_components %}<tr><td>{{ c.name }}</td><td><span class="b {% if c.status == 'Managed' %}bp{% else %}bsk{% endif %}">{{ c.status }}</span></td><td>{{ c.role }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== ECOSYSTEM ===== #}
{% if 'ecosystem' in sections and d.get('ecosystem') %}
<div class="tp" id="t-ecosystem"><div class="ct">
<div class="st">에코시스템 서비스</div><p class="ss">PoC 환경 보조 인프라</p>
<div class="tc"><table><thead><tr><th>카테고리</th><th>서비스</th><th>네임스페이스</th><th>용도</th><th>프로덕션 대체</th></tr></thead><tbody>
{% for eco in d.ecosystem %}<tr{% if eco.get('highlight') %} style="background:var(--{{ eco.highlight }}bg)"{% endif %}><td>{{ eco.category }}</td><td><strong>{{ eco.service }}</strong></td><td>{{ eco.namespace }}</td><td>{{ eco.purpose }}</td><td>{{ eco.prod_alt }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== WBS ===== #}
{% if 'wbs' in sections and d.get('wbs') %}
<div class="tp" id="t-wbs"><div class="ct">
<div class="st">WBS (Work Breakdown Structure)</div><p class="ss">PoC 수행 단계별 작업 분해</p>
<div class="tc"><table><thead><tr><th>Phase</th><th>작업</th><th>런북</th><th>소요</th><th>상태</th></tr></thead><tbody>
{% set cur_phase = namespace(val='') %}
{% for w in d.wbs %}
{% if w.get('phase_title') and w.phase != cur_phase.val %}{% set cur_phase.val = w.phase %}
<tr style="background:var(--passbg)"><td colspan="5" style="font-weight:700;font-size:13px">{{ w.phase_title }}</td></tr>
{% endif %}
<tr><td>{{ w.id }}</td><td>{{ w.task }}</td><td>{{ w.runbook }}</td><td>{{ w.duration }}</td><td><span class="b {% if '완료' in w.status %}bp{% else %}bsk{% endif %}">{{ w.status }}</span></td></tr>
{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== REQUIREMENTS ===== #}
{% if 'requirements' in sections and d.get('requirements') %}
<div class="tp" id="t-requirements"><div class="ct">
<div class="st">전체 요구사항</div><p class="ss">{{ d.requirements|length }}개 항목</p>
<div class="tc"><table><thead><tr><th>No</th><th>분류</th><th>항목</th><th>구분</th><th>상태</th><th>비고</th></tr></thead><tbody>
{% for r in d.requirements %}<tr><td>{{ r.no }}</td><td>{{ r.category }}</td><td>{{ r.item }}</td><td>{{ r.group }}</td><td><span class="b {{ SB.get(r.status,('bsk','?'))[0] }}">{{ SB.get(r.status,('?','?'))[1] }}</span></td><td>{{ r.note }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== GAPS ===== #}
{% if 'gaps' in sections %}
<div class="tp" id="t-gaps"><div class="ct">
<div class="st">Product Gap</div><p class="ss">제품 제한사항 및 리스크 평가</p>
<div class="gg">
{% for g in d.gaps %}<div class="gc"><div class="gt">{{ g.tag }}</div><h4>{{ g.title }}</h4><p>{{ g.desc }}</p>
{% if g.get('impact') %}<p style="margin-top:6px;font-size:10px"><strong>영향:</strong> <span class="{% if g.impact == '높음' %}risk-high{% elif g.impact == '중' %}risk-med{% else %}risk-low{% endif %}">{{ g.impact }}</span> | <strong>대응:</strong> {{ g.get('mitigation','-') }}</p>{% endif %}
</div>{% endfor %}
</div>
{% if d.get('persona_insight') and d.persona_insight.get('gaps') %}
<div class="insight"><div class="tag">{{ d.persona_insight.gaps.get('persona','Expert') }} View</div><h4>{{ d.persona_insight.gaps.get('title','') }}</h4><p>{{ d.persona_insight.gaps.get('body','') }}</p></div>
{% endif %}
</div></div>
{% endif %}

{# ===== RESOLVED ===== #}
{% if 'resolved' in sections %}
<div class="tp" id="t-resolved"><div class="ct">
<div class="st">해소 이력</div><p class="ss">이전 미완료 항목 해소 현황</p>
<div class="tc"><table><thead><tr><th>No</th><th>항목</th><th>이전</th><th>현재</th><th>해소 방법</th><th>런북</th></tr></thead><tbody>
{% for r in d.resolved %}<tr><td>{{ r.no }}</td><td>{{ r.item }}</td><td><span class="b {{ SB.get(r.prev,('bsk','?'))[0] }}">{{ SB.get(r.prev,('?','?'))[1] }}</span></td><td><span class="b {{ SB.get(r.current,('bsk','?'))[0] }}">{{ SB.get(r.current,('?','?'))[1] }}</span></td><td>{{ r.method }}</td><td>{{ r.runbook }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== PERSONAS ===== #}
{% if 'personas' in sections and d.get('personas') %}
<div class="tp" id="t-personas"><div class="ct">
<div class="st">페르소나 검증</div><p class="ss">역할별 PoC 적합성 평가</p>
{% if d.personas.get('kpi') %}
<div class="kg">
{% for pk in d.personas.kpi %}<div class="kc"><div class="kl">{{ pk.label }}</div><div class="kv" style="color:var(--pass);font-size:20px">{{ pk.value }}</div><div class="ks">{{ pk.sub }}</div></div>{% endfor %}
</div>
{% endif %}
{% if d.personas.get('table') %}
<div class="tc"><table><thead><tr><th>페르소나</th><th>평가</th><th>강점</th><th>보완</th></tr></thead><tbody>
{% for pt in d.personas.table %}<tr><td><strong>{{ pt.persona }}</strong></td><td><span class="b {{ SB.get(pt.status,('bsk','?'))[0] }}">{{ pt.verdict }}</span></td><td>{{ pt.strengths }}</td><td>{{ pt.improve }}</td></tr>{% endfor %}
</tbody></table></div>
{% endif %}
{% if d.personas.get('overall') %}
<div style="margin-top:12px;padding:14px 18px;background:var(--card);border-radius:10px;border:1px solid var(--bd);font-size:12px">
<strong>종합: {{ d.personas.overall.verdict }}</strong> | 프로덕션 준비도: <strong>{{ d.personas.overall.readiness }}</strong> | Critical {{ d.personas.overall.critical }}건 | Major {{ d.personas.overall.major }}건
</div>
{% endif %}
</div></div>
{% endif %}

{# ===== EXPERTS ===== #}
{% if 'experts' in sections and d.get('personas') and d.personas.get('experts') %}
<div class="tp" id="t-experts"><div class="ct">
<div class="st">전문가 실증 검증</div>
<div class="tc"><table><thead><tr><th>전문가</th><th>판정</th><th>핵심 근거</th></tr></thead><tbody>
{% for ex in d.personas.experts %}<tr><td><strong>{{ ex.expert }}</strong></td><td><span class="b {{ SB.get(ex.status,('bsk','?'))[0] }}">{{ ex.verdict }}</span></td><td>{{ ex.basis }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== RISK MATRIX ===== #}
{% if 'risk_matrix' in sections and d.get('gaps') %}
<div class="tp" id="t-risk_matrix"><div class="ct">
<div class="st">리스크 매트릭스</div><p class="ss">Product Gap의 영향도/발생가능성 평가</p>
<div class="tc"><table><thead><tr><th>Gap</th><th>제목</th><th>영향도</th><th>발생가능성</th><th>대응 방안</th></tr></thead><tbody>
{% for g in d.gaps %}{% if g.get('impact') %}<tr><td>{{ g.tag }}</td><td>{{ g.title }}</td><td><span class="{% if g.impact == '높음' %}risk-high{% elif g.impact == '중' %}risk-med{% else %}risk-low{% endif %}">{{ g.impact }}</span></td><td>{{ g.get('likelihood','-') }}</td><td>{{ g.get('mitigation','-') }}</td></tr>{% endif %}{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== SCREENSHOTS ===== #}
{% if 'screenshots' in sections and d.get('screenshots') %}
<div class="tp" id="t-screenshots"><div class="ct">
<div class="st">스크린샷 갤러리</div><p class="ss">PoC 수행 중 수집된 주요 화면</p>
<div class="tc"><table><thead><tr><th>카테고리</th><th>화면</th><th>설명</th><th>상태</th></tr></thead><tbody>
{% for ss in d.screenshots %}<tr><td>{{ ss.category }}</td><td>{{ ss.screen }}</td><td>{{ ss.desc }}</td><td><span class="b bv">{{ ss.status }}</span></td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== CONCLUSION ===== #}
{% if 'conclusion' in sections %}
<div class="tp" id="t-conclusion"><div class="ct">
<div class="st">결론 및 권장사항</div>
<div class="cn" style="margin-top:20px"><h3>{{ d.conclusion.title }}</h3><ul>
{% for hl in d.conclusion.highlights %}<li>{{ hl }}</li>{% endfor %}
</ul></div>
{% if d.conclusion.get('recommendations') %}
<div class="tc" style="margin-top:24px"><table><thead><tr><th>권장사항</th><th>우선순위</th><th>상세</th></tr></thead><tbody>
{% for rec in d.conclusion.recommendations %}<tr><td>{{ rec.item }}</td><td><span class="b {{ SB.get(rec.status,('bsk','?'))[0] }}">{{ rec.priority }}</span></td><td>{{ rec.detail }}</td></tr>{% endfor %}
</tbody></table></div>
{% endif %}
{% if d.get('persona_insight') and d.persona_insight.get('conclusion') %}
<div class="insight"><div class="tag">{{ d.persona_insight.conclusion.get('persona','Expert') }} View</div><h4>{{ d.persona_insight.conclusion.get('title','') }}</h4><p>{{ d.persona_insight.conclusion.get('body','') }}</p></div>
{% endif %}
</div></div>
{% endif %}

{# ===== PRODUCTION ROADMAP ===== #}
{% if 'production_roadmap' in sections %}
<div class="tp" id="t-production_roadmap"><div class="ct">
<div class="st">프로덕션 전환 로드맵</div>
<div class="tc"><table><thead><tr><th>우선순위</th><th>영역</th><th>현재</th><th>목표</th><th>작업</th></tr></thead><tbody>
{% for pr in d.production_roadmap %}<tr><td><span class="b {% if pr.priority=='P0' %}bp{% elif pr.priority=='P1' %}bc{% else %}bv{% endif %}">{{ pr.priority }}</span></td><td>{{ pr.area }}</td><td>{{ pr.current }}</td><td>{{ pr.target }}</td><td>{{ pr.action }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

{# ===== COST ALLOCATION ===== #}
{% if 'cost_allocation' in sections and d.get('cost_allocation') %}
<div class="tp" id="t-cost_allocation"><div class="ct">
<div class="st">GPU 비용 할당 설계안</div>
<div class="tc"><table><thead><tr><th>계층</th><th>구분</th><th>메트릭</th><th>구현</th></tr></thead><tbody>
{% for l in d.cost_allocation.layers %}<tr><td>{{ l.level }}</td><td>{{ l.basis }}</td><td>{{ l.metric }}</td><td>{{ l.method }}</td></tr>{% endfor %}
</tbody></table></div>
{% if d.cost_allocation.get('kueue_queues') %}
<div class="tc" style="margin-top:20px"><table><thead><tr><th>ClusterQueue</th><th>GPU</th><th>선점</th><th>대상</th></tr></thead><tbody>
{% for q in d.cost_allocation.kueue_queues %}<tr><td>{{ q.queue }}</td><td>{{ q.gpu_alloc }}</td><td>{{ q.preemption }}</td><td>{{ q.target_team }}</td></tr>{% endfor %}
</tbody></table></div>
{% endif %}
</div></div>
{% endif %}

{# ===== REVISIONS ===== #}
{% if 'revisions' in sections and d.meta.get('revisions') %}
<div class="tp" id="t-revisions"><div class="ct">
<div class="st">변경 이력</div>
<div class="tc"><table><thead><tr><th>버전</th><th>날짜</th><th>작성자</th><th>내용</th></tr></thead><tbody>
{% for rev in d.meta.revisions %}<tr><td><strong>{{ rev.version }}</strong></td><td>{{ rev.date }}</td><td>{{ rev.author }}</td><td>{{ rev.summary }}</td></tr>{% endfor %}
</tbody></table></div>
</div></div>
{% endif %}

<div class="ft2"><p>{{ d.meta.footer }}</p></div>

<script>
function TT(){var d=document.body.getAttribute('data-theme')==='dark';document.body.setAttribute('data-theme',d?'':'dark');var b=document.querySelector('.thm');if(b)b.textContent=d?'Dark Mode':'Light Mode'}
function SW(id,b){document.querySelectorAll('.tp').forEach(function(p){p.classList.remove('a')});document.querySelectorAll('.tb').forEach(function(x){x.classList.remove('a')});var el=document.getElementById('t-'+id);if(el)el.classList.add('a');b.classList.add('a')}
function TA(r){r.classList.toggle('o');r.nextElementSibling.classList.toggle('o')}
{% if variant != 'print' %}
document.addEventListener('DOMContentLoaded',function(){
var c1=document.getElementById('c1');
if(c1)new Chart(c1,{type:'doughnut',data:{labels:['PASS','Out-of-scope'],datasets:[{data:[{{ d.summary.verified_count }},6],backgroundColor:['#10B981','#6B7280'],borderWidth:0}]},options:{cutout:'65%',plugins:{legend:{position:'bottom',labels:{padding:14,usePointStyle:true,pointStyle:'circle'}}}}});
var c2=document.getElementById('c2');
if(c2)new Chart(c2,{type:'bar',data:{labels:['시나리오','Exploratory','OOS'],datasets:[{label:'검증',data:[52,27,0],backgroundColor:'#10B981'},{label:'OOS',data:[0,0,6],backgroundColor:'#6B7280'}]},options:{responsive:true,maintainAspectRatio:false,scales:{x:{stacked:true},y:{stacked:true,beginAtZero:true}}}});
{% if typeof mermaid !== 'undefined' %}mermaid.initialize({startOnLoad:true,theme:document.body.getAttribute('data-theme')==='dark'?'dark':'default'});{% endif %}
});
{% endif %}
</script>
</body>
</html>
'''


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="RHOAI PoC 보고서 생성기")
    p.add_argument("base", type=Path, help="기본 TOML 데이터 파일")
    p.add_argument("--overlay", type=Path, help="변형 오버레이 TOML")
    p.add_argument("--variant", type=str, help="변형 이름 (overlay 대신)")
    p.add_argument("-o", "--output", type=Path, default=Path("report.html"))
    return p.parse_args()


def main() -> None:
    args = parse_args()
    data = load_toml(args.base)

    if args.overlay:
        data = deep_merge(data, load_toml(args.overlay))
    elif args.variant:
        vp = args.base.parent / "variants" / f"{args.variant}.toml"
        if vp.exists():
            data = deep_merge(data, load_toml(vp))
        elif args.variant in VARIANT_DEFAULTS:
            data = deep_merge(data, {"template": {"variant": args.variant}})
        else:
            print(f"변형 '{args.variant}'을 찾을 수 없습니다.", file=sys.stderr)
            sys.exit(1)

    html = build_html(data)
    args.output.write_text(html, encoding="utf-8")
    print(f"생성 완료: {args.output}")


if __name__ == "__main__":
    main()
