# 테스트 기능 카탈로그와 단계별 실행 후보

- 작성일: 2026-04-30
- 최종 수정: 2026-05-17
- 상태: **폐기 (Deprecated)** — v1~v3에서 28개 중 18개 달성. 잔여 항목은 009로 이관.
- 실행 여부: **미참조. 역사적 의사결정 기록으로만 보존.**

> **⚠️ 이 문서는 더 이상 참조되지 않습니다.**
> Session 24(2026-04-30)에 작성된 후속 테스트 백로그.
> - K8S/NET/GW/AI 후보 18개 → v1~v3 S1~S10에서 검증 완료
> - MCP/가상화/멀티클러스터 → `009-roadmap-v4.md` Phase M으로 이관
> - 런북 번호 후보(70~77) → 실제와 불일치 (70~79는 검증 런북)

## Why (왜 이 문서가 필요한가)

Scope 4/5 이전에 가상화, MCP 관리, HA, Gateway, CI/CD, AI Pipeline, 네트워크 기능을 한꺼번에 실행 범위로 올리면 cold-start 기준점이 흔들린다. 다음 세션의 명확한 중단 지점은 여전히 **Scope 4: PoC Application 편입**이어야 한다.

이 문서는 새 Scope가 아니라 후속 테스트 후보 백로그다. 실행은 Scope 4/5 완료 후 사람이 하나를 선택하고, `active-task.md`에 단일 태스크로 승격한 뒤 CHECKPOINT를 거쳐 진행한다.

## Guardrails (흔들림 방지 원칙)

- `active-task.md`는 항상 다음에 실행할 태스크 1개만 담는다.
- 이 문서의 항목은 실행 대기 후보이며, 자동으로 클러스터 변경 대상이 되지 않는다.
- 각 후보는 별도 `runbooks/7x-*.md`와 `infra/poc/<name>/`를 만든 뒤 실행한다.
- cluster-scoped 변경이 필요한 후보는 반드시 별도 work-plan을 먼저 작성한다.
- 모든 테스트 Application은 기본 `prune=false`, 수동 sync, drift 확인 후 다음 단계로 넘어간다.
- 멀티 클러스터와 가상화는 영향도가 크므로 단일 클러스터 기본 테스트가 안정된 뒤 진행한다.

## 실행 승격 절차

1. Scope 4 완료 — 기존 PoC(`workbench-smoke`, `llm-cpu`) ArgoCD 편입
2. Scope 5 완료 — 전체 `Synced/Healthy`, drift 0 확인
3. 사람이 아래 카탈로그에서 후보 1개 선택
4. 선택 후보를 `active-task.md`의 단일 태스크로 승격
5. 필요한 runbook/IaC 작성
6. CHECKPOINT 승인 후 dry-run → apply/sync → smoke 검증
7. `current-state.md`, `active-task.md`, `handoff-notes.md` 갱신 후 커밋

## 후보 요약

| ID | 영역 | 후보 | 우선순위 | 리스크 | 필요 리소스 | 성공 기준 | 실행 단위 |
|---|---|---|---|---|---|---|---|
| K8S-01 | Kubernetes 기본 | rollout/rollback + probe smoke | P0 | 낮음 | namespace, sample app | rollout 성공, rollback 성공, readiness/liveness 동작 | `infra/poc/k8s-rollout-smoke` |
| K8S-02 | Kubernetes 기본 | PDB + replica HA | P0 | 낮음 | namespace, 2~3 replica app | pod kill/drain 유사 상황에서 최소 가용성 유지 | `infra/poc/k8s-pdb-ha` |
| K8S-03 | Kubernetes 기본 | requests/limits + HPA | P1 | 중간 | metrics, load generator | 부하 시 scale out/in 확인 | `infra/poc/k8s-hpa-smoke` |
| K8S-04 | Kubernetes 기본 | quota/LimitRange/RBAC | P1 | 낮음 | namespace, Role/RoleBinding | 제한 초과 차단, 최소권한 동작 | `infra/poc/k8s-policy-smoke` |
| NET-01 | 네트워크 | DNS + Service discovery | P0 | 낮음 | namespace, client/server pod | ClusterIP/headless DNS 확인 | `infra/poc/net-service-discovery` |
| NET-02 | 네트워크 | NetworkPolicy allow/deny | P0 | 중간 | namespace, isolated pods | 허용 경로만 통신 성공 | `infra/poc/net-networkpolicy` |
| NET-03 | 네트워크 | egress 제어 | P2 | 중간 | egress 테스트 pod | 허용/차단 경로 구분 | `infra/poc/net-egress-policy` |
| GW-01 | Gateway/트래픽 | Gateway API + HTTPRoute smoke | P0 | 중간 | Gateway/HTTPRoute, sample app | route 정상, TLS/host 확인 | `infra/poc/gateway-http-route` |
| GW-02 | Gateway/트래픽 | blue/green routing | P1 | 중간 | 2 version app | 트래픽 전환 확인 | `infra/poc/gateway-bluegreen` |
| GW-03 | Gateway/트래픽 | weighted canary / A/B | P1 | 중간 | 2 version app, headers/weights | weight 또는 header 기준 분기 확인 | `infra/poc/gateway-canary-ab` |
| HA-01 | 애플리케이션 HA | app HA + fault smoke | P0 | 낮음 | 3 replica app | 일부 pod 장애에도 서비스 유지 | `infra/poc/app-ha-smoke` |
| HA-02 | 애플리케이션 HA | node drain 영향 관찰 | P2 | 높음 | admin 권한, PDB app | drain 전후 영향 기록 | 별도 승인 필요 |
| CICD-01 | CI/CD | Pipeline build/test smoke | P1 | 중간 | OpenShift Pipelines, sample repo/image | test 통과 시 image 생성 | `infra/poc/cicd-pipeline-smoke` |
| CICD-02 | CI/CD | GitOps promotion | P1 | 중간 | Git branch/tag 전략 | Pipeline은 manifest 갱신, ArgoCD는 배포 | `infra/poc/cicd-gitops-promotion` |
| AI-01 | RHOAI | DataSciencePipeline smoke | P0 | 중간 | RHOAI pipeline namespace/PVC | 간단 pipeline 성공 | `infra/poc/ai-pipeline-smoke` |
| AI-02 | RHOAI | Model Registry smoke | P1 | 중간 | registry 설정 | model metadata 등록/조회 | `infra/poc/ai-model-registry-smoke` |
| AI-03 | RHOAI | model serving 추가 smoke | P1 | 중간 | small model, KServe | `/v1/models` 또는 inference 성공 | `infra/poc/ai-serving-smoke` |
| AI-04 | RHOAI | serving autoscaling | P2 | 중간 | load generator | min/max replica 동작 확인 | `infra/poc/ai-serving-autoscale` |
| VIRT-01 | 가상화 | OpenShift Virtualization 설치 판단 | P2 | 높음 | cluster survey | 설치 가능성/리소스/스토리지 판단만 | 별도 work-plan |
| VIRT-02 | 가상화 | VM smoke | P2 | 높음 | OpenShift Virtualization, PVC | VM Running, console/network 확인 | `infra/poc/virt-vm-smoke` |
| VIRT-03 | 가상화 | VM network/storage/snapshot | P3 | 높음 | VM, PVC, snapshot class | VM 서비스 노출/복구 확인 | 별도 work-plan |
| MCP-01 | MCP 관리 | MCP server inventory + healthcheck | P1 | 낮음 | 문서/설정, optional pod | 서버 목록/상태/소유권 정리 | `infra/poc/mcp-healthcheck` |
| MCP-02 | MCP 관리 | MCP RBAC/permission policy | P1 | 중간 | policy 문서, optional service account | 읽기/쓰기 경계 검증 | `infra/poc/mcp-rbac-policy` |
| MCP-03 | MCP 관리 | internal service MCP demo | P2 | 중간 | internal demo service | MCP를 통한 read-only 진단 성공 | `infra/poc/mcp-internal-demo` |
| MC-01 | 멀티 클러스터 | GitOps fan-out 설계 | P3 | 높음 | 두 번째 클러스터 또는 ACM | 설계/제약 정리 | 별도 work-plan |
| MC-02 | 멀티 클러스터 | failover/DR smoke | P3 | 높음 | 멀티 클러스터 | 장애/전환 시나리오 검증 | 별도 work-plan |

## 추천 실행 순서

1. K8S-01 rollout/rollback + probe smoke
2. K8S-02 PDB + replica HA
3. NET-01 DNS + Service discovery
4. NET-02 NetworkPolicy allow/deny
5. GW-01 Gateway API + HTTPRoute smoke
6. GW-02 blue/green routing
7. GW-03 weighted canary / A/B
8. CICD-01 Pipeline build/test smoke
9. CICD-02 GitOps promotion
10. AI-01 DataSciencePipeline smoke
11. AI-02 Model Registry smoke
12. MCP-01 MCP server inventory + healthcheck
13. MCP-02 MCP RBAC/permission policy
14. VIRT-01 OpenShift Virtualization 설치 판단
15. MC-01 GitOps fan-out 설계

## Runbook 번호 후보

| 번호 | 주제 | 비고 |
|---|---|---|
| `70-k8s-basic-ha.md` | rollout, probe, PDB, HPA, quota/RBAC | K8S-01~04 |
| `71-network-functions.md` | DNS, Service, NetworkPolicy, egress | NET-01~03 |
| `72-gateway-traffic.md` | Gateway, blue/green, canary, A/B | GW-01~03 |
| `73-cicd-gitops.md` | Pipeline, promotion, rollback | CICD-01~02 |
| `74-rhoai-ai-pipeline.md` | DSP, registry, serving 확장 | AI-01~04 |
| `75-mcp-management.md` | MCP inventory, healthcheck, RBAC | MCP-01~03 |
| `76-virtualization.md` | OpenShift Virtualization 판단/VM smoke | VIRT-01~03 |
| `77-multicluster.md` | 멀티 클러스터 설계/DR | MC-01~02 |

## 첫 번째 후보 상세: K8S-01

K8S-01은 Scope 5 이후 가장 먼저 실행하기 좋은 테스트다. cluster-scoped 변경 없이 namespace 안에서 배포, probe, rollout, rollback을 확인할 수 있어 실패 영향이 작다.

성공 기준:

- sample Deployment `Available=True`
- readinessProbe 실패 시 Service endpoint에서 제외
- livenessProbe 실패 시 container restart 확인
- image 또는 config 변경 rollout 성공
- 이전 revision rollback 성공
- ArgoCD Application `Synced/Healthy`

중단 기준:

- sample app이 시스템 네임스페이스 또는 기존 리소스를 요구함
- cluster-scoped 권한이 필요해짐
- HPA/Gateway/NetworkPolicy 등 다른 후보 범위로 번짐

## Open Questions (폐기 시점 기준)

- [x] ~~Scope 5 이후 첫 실행 후보~~ → v1~v3로 대체 달성
- [ ] MCP 관리 → v4 범위 외
- [ ] 가상화 테스트 → v4 범위 외
- [ ] 멀티 클러스터 → `009-roadmap-v4.md` Phase M

## References

- work-plans/009-roadmap-v4.md — 잔여 항목 이관 대상
- work-plans/005-customer-rtm.md — 실제 검증 항목 (S1~S10)
- reviews/pmo-document-audit.md — 003 폐기 판단 근거
