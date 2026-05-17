# IaC 이식 가이드

- 작성일: 2026-05-17
- 최종 수정: 2026-05-17

## Why

다른 클러스터(고객 환경, HGX, 에어갭)에 동일 PoC를 재현할 때 변경 범위를 최소화하기 위해 이식 가이드를 정리한다.

## How

다른 클러스터에 이 IaC를 배포할 때 변경해야 하는 항목.

## 필수 변경

### 1. ArgoCD Repository URL

bootstrap `kustomization.yaml`의 `gitops-repo-config` ConfigMap에서 `repoURL`만 변경하면 모든 Application에 일괄 주입됨.

### 2. LDAP 비밀번호

`infra/poc/ldap/openldap.yaml`의 `DS_DM_PASSWORD`를 실제 값으로 교체. group-sync는 `bindPassword.file`로 파일 참조.

### 3. S3 연결 정보

`poc-s3-connection` Secret을 클러스터별 S3 엔드포인트/인증으로 재생성.

## 선택 변경

| 항목 | 현재 값 | 변경 방법 |
|------|--------|----------|
| 네임스페이스 | rhoai-poc 등 | namespace.yaml 또는 Kustomize overlay |
| Operator 채널 | stable, latest 등 | subscription.yaml channel 수정 |
| GPU 설정 | L40S | cluster-policy.yaml 조정 |

## 변경 불필요

- Kustomize 구조, ArgoCD Application 패턴
- 런북 환경변수 (`${POC_NAMESPACE}` 등)
- Operator 설치 순서 (6-Layer)
- RBAC / NetworkPolicy 구조

## Tradeoffs

- `.env.example` 기반 변수화 vs Kustomize overlay: overlay가 GitOps 친화적이지만 초기 진입 장벽 있음
- SealedSecret vs ExternalSecret: 클러스터 간 이동 시 Secret 관리 방식 결정 필요

## Decision

현재는 `.env.example` + Kustomize overlay(dev/staging/prod) 병행. Secret은 평문(PoC), 프로덕션 전환 시 SealedSecret 도입.

## Open Questions

- [ ] 에어갭 환경에서 modelcar 이미지 미러링 절차
- [ ] HGX 클러스터의 GPU profile overlay 검증

## References

- work-plans/009-roadmap-v4.md — Phase J (Kustomize overlay)
- infra/poc/overlays/ — 실제 overlay 구조
