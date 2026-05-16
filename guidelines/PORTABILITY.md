# IaC 이식 가이드

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
