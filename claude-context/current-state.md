# 현재 상태 (2026-05-22 Session 40b 기준)

> **프로젝트 목적: "AI와 IaC를 활용한 고객 시나리오 기반 RHOAI PoC 수행".** poc-factory는 폐기되었으며, 필요한 문서(런북, 시나리오, 검증 항목)를 이 프로젝트에 흡수 완료. 런북 v3 완성, 리포트 12스프린트 재구축 완료.

## 클러스터 인덱스

| 클러스터 | 환경 | GPU | 용도 | 상태 파일 |
|----------|------|-----|------|-----------|
| **Sandbox** | AWS / Connected | L40S×4 | 런북 개발·검증, 시나리오 실측, 리포트 | [current-state-sandbox.md](current-state-sandbox.md) |
| **Mobis PoC** | bare metal / Restricted | H200×8 + A40×2 | 고객 대상 실제 PoC | [current-state-mobis.md](current-state-mobis.md) |

세션 시작 시 작업 대상 클러스터의 상태 파일을 읽을 것.

## 구조 변경 진행 현황 (Session 30~38b)

- [x] `CLAUDE.md` — 목적 재정의, POC 환경 추가, PoC 프로세스 추가, 3자리 넘버링 현행화
- [x] `work-plans/004-poc-restructure.md` — 의사결정 기록
- [x] `guidelines/01-layer-contracts.md` — 넘버링 세분화 (300~390 구축/500~590 검증/800 종합), reports/ 추가
- [x] `reports/_template/README.md` — 산출물 템플릿
- [x] `work-plans/005-mobis-rtm.md` — RTM 작성 완료 (S1~S6 + Exploratory + Out-of-scope)
- [x] 런북 변환 완료 — 70~75 검증 런북 + 80 종합 검증 신규 작성
- [x] current-state 클러스터별 분리 — sandbox / mobis 독립 파일
- [x] 런북 이식성 환경변수화 (22개 런북, .env.example GPU 스펙 12변수)
- [x] Perses 대시보드 12개 정상 (MaaS Token/Usage Trend 포함)
- [x] COO MonitoringStack 알림 E2E (PrometheusRule → AlertManager → MailHog)
- [x] 모델 카탈로그 에어갭 적용 (13모델 + validated 74모델)
- [x] IaC 전면 동기화 — Operator 16개 + DSC/DSCI + Gateway + cluster-config (kustomize 9/9 PASS)
- [x] LVMCluster vg-master /dev/sda→/dev/sdb 패치 + 트러블슈팅
- [x] 시나리오 시연 문서 12개 작성 (S1~S11 + S6b) — 15스프린트 저지 검증 완료
- [x] 시나리오 20스프린트 실증 검증 — IS Ready, Pod 복구 5초, KEDA Ready 등 실측
- [x] ServingRuntime 이미지 복원 (image 필드 누락 → ReconcileFailed 해소)
- [x] GenAI Playground 크래시 해결 (LLMInferenceService nil pointer → 삭제)
- [x] htpasswd 3계정 생성 (poc-admin/poc-operator/poc-user 로그인 성공)
- [x] Pipeline CR 2개 생성 (model-serving-e2e + model-e2e-7stage)
- [x] IaC cluster-config 신규 — KubeletConfig/Chrony/DNS/LVMS/MetalLB/NMState/OAuth/Proxy (48 resources)
- [x] 스프레드시트 데이터 통합 — 85항목 런북/IaC/시나리오/실측값 기입
- [x] 런북 넘버링 문서 최신화 (78개 런북, 번호 충돌 2건 식별)
- [x] 클러스터 헬스체크 대시보드 스크립트 (scripts/cluster-health-check.sh, watch 모드)
- [x] 관측성 트러블슈팅 8건 해소 (Perses datasource/토큰/CPU, ds-pipeline/istio/trustyai 타겟, RHOAI UI)
- [x] IaC perses-datasource.yaml default:false 변경 (RHOAI datasource 충돌 해소)
- [x] Gateway API HTTPRoute 카나리 배포 구현 (canaryTrafficPercent→HTTPRoute weight 대체)
- [x] 비용 할당 리포트 Tekton Pipeline (RTM No.62 OOS→부분검증 격상, 3 subscription $97.30 실측)
- [x] subscription→부서/팀 매핑 검증 Task + ConfigMap 기반 매핑 테이블
- [x] etcd defrag (1.1GB→402MB) + CPU/etcd/NTP 알림 silence
- [x] NTP chrony 에어갭 설정 (MachineConfig 적용, MCP 렌더링 완료)
- [x] CoreDNS maas→10.240.252.81 정상 확인 (Pod DNS 정상)
- [x] LDAP 연동 (OAuth IDP mobis-ldap, Service_rhoai 로그인 성공)
- [x] LDAP 그룹 동기화 (정보화추진팀 14명 + 데이터사이언스팀 21명)
- [x] 매핑 관리 Pipeline 분리 (team-mapping-pipeline add/list/delete)
- [x] SMTP 실제 서버 전환 (10.240.13.184:25, @mobisdev-partners.com)
- [x] Task 이미지 전체 내부 레지스트리 전환 (Restricted 환경 대응)

## 현재 Mobis 클러스터 리소스 상태

| 리소스 | 상태 | 수량 |
|--------|------|------|
| Operators (CSV) | 전체 정상 | 25개 |
| InferenceService | smollm2-135m Ready, smollm2-s5-zero Ready | 2 |
| ServingRuntime | vllm-cuda-runtime (이미지 복원 완료) | 1 |
| Tekton Pipeline | model-e2e-7stage, cost-allocation-report, team-mapping | 3 |
| Tekton Task | 9개 (기존 6 + cost-allocation-report + validate-team-mapping + manage-team-mapping) | 9 |
| LDAP 연동 | OAuth IDP mobis-ldap, 그룹 2개 (정보화추진팀 14명 + 데이터사이언스팀 21명) | 2 그룹 |
| ManualApprovalGate | Ready=True v0.8.0 | 1 |
| KEDA ScaledObject | vllm-autoscaler, s5-http-scaler | 2 |
| Perses Dashboard | 12개 | 12 |
| PrometheusRule | poc-gpu-alerts, vllm-alerts | 2 |
| HardwareProfile | 7개 (cpu-small ~ gpu-xlarge + a40-test) | 7 |
| MinIO / MailHog / DSPA | Running | 3 |
| Model Registry | 3 Pod Running | 3 |
| htpasswd 사용자 | poc-admin, poc-operator, poc-user | 3 |
| Dashboard (rhods-dashboard) | 9/9 Running (gen-ai-ui 복구 완료) | 2 Pod |

## IaC 현황

| 디렉토리 | 파일 | kustomize |
|---------|------|-----------|
| infra/cluster-config/ | 15 (kubelet/chrony/dns/lvms/metallb/nmstate/oauth/proxy) | PASS (14 resources) |
| infra/openshift-ai/ | 4 (dsc/dsci/manual-approval-gate) | PASS (3 resources) |
| infra/operators/ | 16개 디렉토리 | PASS |
| infra/poc/ | 14개 디렉토리 (model-serving/pipeline/dspa/autoscaling/monitoring 등) | PASS |
| infra/rhoai/ | dashboards(9)/hardwareprofiles(7)/gateway/evalhub/observability | PASS |
| **총** | **226개 YAML** | **전체 PASS** |
