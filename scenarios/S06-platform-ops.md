# S6: 운영관리 — LDAP/RBAC 기반 플랫폼 거버넌스

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | INFRA → MGR |
| 보조역할 | OPS |
| 데모 시간 | 20분 |
| 검증 항목 | No.14, 15, 16, 44, 45, 46, 68, 69, 70 |
| 구축 런북 | `runbooks/350-platform-ops.md`, `runbooks/352-ldap.md`, `runbooks/353-platform-ops-v3.md` |
| 검증 런북 | `runbooks/550-platform-ops-validation.md` |
| IaC | `infra/poc/ldap/` |

---

## 상황 (Context)

> 현대모비스 AI CoE(Center of Excellence)는 자율주행 영상 분석, 차량 음성 인식, 품질 예측 등 다양한 AI 프로젝트를 동시에 운영합니다. 현재 약 200명의 인원이 5개 팀으로 나뉘어 작업하며, 기존 Active Directory(AD)에 조직도가 관리되고 있습니다.
>
> AI 플랫폼을 도입하면서, 기존 AD 인프라를 **그대로 재활용**하여 팀별 접근 권한을 자동으로 분리하고, GPU 자원을 공정하게 배분하며, 모든 조작이 감사 추적(audit trail) 가능해야 합니다.

## 문제 (Problem)

> 기존 방식에서는 이런 문제가 있습니다:
>
> 1. **계정 이중 관리**: AI 플랫폼 전용 계정을 별도로 만들면 AD와 동기화가 깨지고, 퇴사자 계정 회수가 누락됩니다.
> 2. **권한 혼재**: 모든 사용자가 동일한 권한으로 GPU 클러스터에 접근하여, 데이터 사이언티스트가 실수로 운영 모델을 삭제하거나 인프라 설정을 변경할 수 있습니다.
> 3. **자원 독점**: 특정 팀이 GPU를 장시간 점유하면 다른 팀의 실험이 지연되지만, 제한할 방법이 없습니다.
> 4. **감사 불가**: 누가 어떤 모델을 배포하고 삭제했는지 추적할 수 없어, 보안 감사 시 대응이 어렵습니다.
> 5. **전용 UI 의존**: 독자 포털에 종속되면 K8s 네이티브 도구(kubectl, GitOps)와 호환이 안 됩니다.

## 해결 (Solution) — RHOAI로 이렇게 해결합니다

### Step 1. 내부 OpenLDAP 배포 — 조직 구조 구성 (3분)

> **누가**: INFRA (poc-admin, cluster-admin)
> **무엇을**: 모비스 조직 구조를 반영한 OpenLDAP 서버 배포
> **어떻게**: Kustomize 기반 IaC로 일관된 배포

```
[시연 포인트]
"실제 환경에서는 기존 AD/LDAP 서버를 그대로 사용합니다.
 PoC에서는 모비스 조직도를 모사한 OpenLDAP을 배포하겠습니다."
```

```bash
# OpenLDAP 배포 (IaC)
oc apply -k infra/poc/ldap/
oc wait -n poc-ldap deployment/openldap --for=condition=Available --timeout=120s
```

```
[화면에 보여줄 것]
조직 트리 구조:
  dc=mobis,dc=local
  ├── ou=users
  │   ├── uid=dev-user1  (dev-team, 데이터 사이언티스트)
  │   ├── uid=dev-user2  (dev-team, ML 엔지니어)
  │   ├── uid=ops-user1  (ops-team, 운영자)
  │   └── uid=mgr-user1  (ops-team, 관리자)
  └── ou=groups
      ├── cn=dev-team
      └── cn=ops-team
```

```bash
# LDAP 트리 확인
LDAP_POD=$(oc get pods -n poc-ldap -l app=openldap -o jsonpath='{.items[0].metadata.name}')
oc exec -n poc-ldap ${LDAP_POD} -- ldapsearch -x -H ldap://localhost:1389 \
  -D "cn=admin,dc=mobis,dc=local" -w admin1234 \
  -b "dc=mobis,dc=local" "(objectClass=*)" dn
```

**확인**: OpenLDAP Pod Running, 사용자 4명 + 그룹 2개 확인

---

### Step 2. OAuth LDAP Identity Provider 구성 (3분)

> **누가**: INFRA (poc-admin, cluster-admin)
> **무엇을**: OpenShift OAuth에 LDAP IdP 등록
> **어떻게**: OAuth CR 수정으로 LDAP 연동 활성화

```
[시연 포인트]
"OCP의 OAuth 시스템에 LDAP 소스를 등록합니다.
 이 한 번의 설정으로, AD에 등록된 모든 사용자가
 OCP와 RHOAI Dashboard에 동시에 로그인할 수 있습니다."
```

```bash
# LDAP Bind Password Secret 생성
oc create secret generic ldap-bind-password \
  -n openshift-config \
  --from-literal=bindPassword=admin1234 \
  --dry-run=client -o yaml | oc apply -f -

# OAuth LDAP IdP 등록
oc apply -f - <<'EOF'
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
    - name: poc-ldap
      type: LDAP
      mappingMethod: claim
      ldap:
        url: "ldap://openldap.poc-ldap.svc.cluster.local:389/ou=users,dc=mobis,dc=local?uid"
        insecure: true
        bindDN: "cn=admin,dc=mobis,dc=local"
        bindPassword:
          name: ldap-bind-password
        attributes:
          id: ["dn"]
          email: ["mail"]
          name: ["cn"]
          preferredUsername: ["uid"]
EOF

# OAuth Pod 재시작 대기
oc wait -n openshift-authentication deployment/oauth-openshift \
  --for=condition=Available --timeout=300s
```

**확인**: OAuth 설정에 `poc-ldap` IdP 등록 확인

---

### Step 3. MGR — LDAP 사용자로 로그인 (2분)

> **누가**: MGR (dev-user1 → LDAP 인증)
> **무엇을**: LDAP 계정으로 OCP + RHOAI Dashboard 로그인
> **어떻게**: 브라우저에서 LDAP IdP 선택 후 로그인

```
[시연 포인트]
"브라우저를 열겠습니다. 로그인 화면에 'poc-ldap'이 새로 나타났습니다.
 dev-user1으로 로그인하면, 이 사용자에게 할당된 네임스페이스만 보입니다."
```

```bash
# CLI로도 확인
oc login ${CLUSTER_API_URL} \
  --username=dev-user1 --password=password1 \
  --insecure-skip-tls-verify=true
oc whoami
# 기대값: dev-user1

# Group Sync 실행
oc adm groups sync \
  --sync-config=infra/poc/ldap/ldap-group-sync.yaml \
  --confirm
oc get groups
# 기대값: dev-team, ops-team 그룹 동기화
```

```
[화면에 보여줄 것]
1. RHOAI Dashboard 로그인 화면 → "poc-ldap" IdP 선택
2. dev-user1 / password1 입력
3. 대시보드 진입 후 → 자신의 네임스페이스만 표시
```

**확인**: LDAP 인증 성공, RHOAI Dashboard 진입, 네임스페이스 격리 확인

---

### Step 4. DS — 읽기 전용 권한 확인 (2분)

> **누가**: DS (poc-user, NS view + serving)
> **무엇을**: 모델 조회는 가능하지만 삭제는 불가능함을 시연
> **어떻게**: RBAC view 역할의 제한 확인

```
[시연 포인트]
"데이터 사이언티스트 계정으로 전환합니다.
 모델 목록은 볼 수 있지만, 삭제 버튼을 누르면 권한 거부됩니다.
 이것이 3단계 RBAC입니다."
```

```bash
# DS 권한 확인
oc auth can-i get inferenceservice -n ${MODEL_NS:-mobis-poc} --as=poc-user
# 기대값: yes (조회 가능)

oc auth can-i delete inferenceservice -n ${MODEL_NS:-mobis-poc} --as=poc-user
# 기대값: no (삭제 불가)

oc auth can-i create inferenceservice -n ${MODEL_NS:-mobis-poc} --as=poc-user
# 기대값: no (생성 불가)

# 3단계 RBAC 구조 확인
oc get rolebinding -n ${MODEL_NS:-mobis-poc} -o custom-columns=\
'NAME:.metadata.name,ROLE:.roleRef.name,USER:.subjects[0].name'
# 기대값:
#   poc-admin  → admin (모든 권한)
#   poc-operator → edit (생성/수정/삭제)
#   poc-user   → view (읽기만)
```

**확인**: 3단계 RBAC 격리 — admin/edit/view 역할 분리

---

### Step 5. HardwareProfile CR — GPU 할당 프리셋 (3분)

> **누가**: INFRA (poc-admin, cluster-admin)
> **무엇을**: GPU 자원 할당 프리셋(HardwareProfile)을 정의하여 표준화
> **어떻게**: HardwareProfile CR로 GPU/메모리 조합을 사전 정의

```
[시연 포인트]
"GPU를 어떤 사이즈로 할당할지 매번 수동 지정하면 실수가 잦습니다.
 HardwareProfile CR로 'Small-1GPU', 'Large-4GPU' 같은 프리셋을 만들어 둡니다.
 사용자는 프리셋만 선택하면 됩니다."
```

```bash
# HardwareProfile CR 확인 (RHOAI 3.4+)
oc get hardwareprofile -n redhat-ods-applications

# 예: GPU 프리셋 정의
oc apply -f - <<'EOF'
apiVersion: dashboard.opendatahub.io/v1alpha1
kind: HardwareProfile
metadata:
  name: gpu-small
  namespace: redhat-ods-applications
spec:
  displayName: "Small GPU (1x GPU, 16Gi)"
  description: "개발/실험용 — GPU 1장 할당"
  enabled: true
  identifiers:
    - displayName: GPU
      identifier: nvidia.com/gpu
      defaultCount: 1
      minCount: 1
      maxCount: 1
    - displayName: Memory
      identifier: memory
      defaultCount: 16
      minCount: 8
      maxCount: 32
  nodeSelectors:
    nvidia.com/gpu.present: "true"
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
EOF

echo "=== 등록된 HardwareProfile ==="
oc get hardwareprofile -n redhat-ods-applications \
  -o custom-columns='NAME:.metadata.name,DISPLAY:.spec.displayName,ENABLED:.spec.enabled'
```

```
[화면에 보여줄 것]
RHOAI Dashboard → Settings → Hardware profiles
→ 'Small GPU', 'Large GPU' 프리셋 목록
→ Workbench 생성 시 드롭다운에서 프리셋 선택
```

**확인**: HardwareProfile CR 등록 및 Dashboard 드롭다운 반영

---

### Step 6. ResourceQuota 적용 — 팀별 자원 제한 (3분)

> **누가**: MGR (poc-operator, NS edit)
> **무엇을**: 네임스페이스 단위 GPU/CPU/메모리 상한선 설정
> **어떻게**: ResourceQuota CR 적용

```
[시연 포인트]
"개발팀에 GPU 2장, 메모리 64Gi 제한을 걸겠습니다.
 이 제한은 쿠버네티스 네이티브 기능이라 우회가 불가능합니다."
```

```bash
# ResourceQuota 적용
oc apply -n ${MODEL_NS:-mobis-poc} -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-gpu-quota
spec:
  hard:
    requests.nvidia.com/gpu: "2"
    limits.nvidia.com/gpu: "2"
    requests.memory: 64Gi
    limits.memory: 128Gi
    requests.cpu: "16"
    limits.cpu: "32"
    pods: "20"
EOF

# 현재 사용량 확인
oc describe resourcequota team-gpu-quota -n ${MODEL_NS:-mobis-poc}
```

```
[화면에 보여줄 것]
ResourceQuota 현황:
  Resource              Used    Hard
  --------              ----    ----
  nvidia.com/gpu        1       2
  memory (requests)     32Gi    64Gi
  pods                  8       20
```

**확인**: ResourceQuota 적용 확인, Used/Hard 비율 표시

---

### Step 7. DS — 쿼터 초과 시도 → 거부 (2분)

> **누가**: DS (poc-user)
> **무엇을**: GPU 쿼터를 초과하는 워크로드 생성 시도 → 거부됨 확인
> **어떻게**: GPU 3장 요청 → 쿼터(2장) 초과 → 스케줄링 거부

```
[시연 포인트]
"데이터 사이언티스트가 GPU 3장을 요청하면 어떻게 될까요?
 쿼터 2장을 초과하므로, 쿠버네티스가 즉시 거부합니다.
 사전에 자원 낭비를 방지하는 것입니다."
```

```bash
# GPU 3장 요청 (쿼터 초과)
oc apply -n ${MODEL_NS:-mobis-poc} -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: quota-test-exceed
spec:
  containers:
    - name: test
      image: nvidia/cuda:12.4.0-base-ubi9
      command: ["sleep", "10"]
      resources:
        limits:
          nvidia.com/gpu: "3"
        requests:
          nvidia.com/gpu: "3"
  restartPolicy: Never
EOF
# 기대: Error — "exceeded quota: team-gpu-quota"

# 거부 메시지 확인
oc get events -n ${MODEL_NS:-mobis-poc} --sort-by='.lastTimestamp' | grep -i quota | tail -3

# 정리
oc delete pod quota-test-exceed -n ${MODEL_NS:-mobis-poc} --ignore-not-found 2>/dev/null
```

**확인**: 쿼터 초과 시 `exceeded quota` 에러 메시지 발생

---

### Step 8. OPS — 3가지 접근 경로 확인 (2분)

> **누가**: OPS (poc-operator, NS edit + monitoring)
> **무엇을**: RHOAI Dashboard, CLI (oc), REST API 세 가지 관리 경로 시연
> **어떻게**: 동일한 작업을 세 가지 방법으로 수행

```
[시연 포인트]
"운영자는 세 가지 방법으로 플랫폼을 관리합니다:
 1) 웹 대시보드 — 시각적 관리
 2) CLI (oc 명령) — 자동화/스크립팅
 3) REST API — 외부 시스템 연동
 모두 동일한 K8s API를 기반으로 합니다."
```

```bash
# 1) RHOAI Dashboard URL
DASHBOARD_URL="https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')"
echo "Dashboard: ${DASHBOARD_URL}"

# 2) CLI로 모델 목록 조회
oc get inferenceservice -n ${MODEL_NS:-mobis-poc}

# 3) REST API로 동일 정보 조회
TOKEN=$(oc whoami -t)
API_URL=$(oc whoami --show-server)
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "${API_URL}/apis/serving.kserve.io/v1beta1/namespaces/${MODEL_NS:-mobis-poc}/inferenceservices" | \
  python3 -c "import sys,json; items=json.load(sys.stdin).get('items',[]); [print(f'  {i[\"metadata\"][\"name\"]}: {i[\"status\"][\"conditions\"][-1][\"type\"]}={i[\"status\"][\"conditions\"][-1][\"status\"]}') for i in items]"
```

**확인**: Dashboard HTTP 200, CLI 응답, REST API JSON 응답 — 세 경로 모두 정상

---

### Step 9. K8s 네이티브 운영 — CRD 기반 관리 (2분)

> **누가**: INFRA (poc-admin)
> **무엇을**: RHOAI의 모든 리소스가 K8s CRD임을 증명
> **어떻게**: CRD 목록 조회 + kubectl/oc/GitOps로 관리 가능함을 시연

```
[시연 포인트]
"RHOAI는 독자 포맷이 아닙니다. InferenceService, ServingRuntime,
 HardwareProfile 등 모든 것이 쿠버네티스 CRD입니다.
 kubectl, Helm, ArgoCD 등 기존 K8s 도구와 100% 호환됩니다."
```

```bash
# RHOAI 관련 CRD 목록
echo "=== RHOAI CRD ==="
for crd in inferenceservices.serving.kserve.io \
           servingruntimes.serving.kserve.io \
           hardwareprofiles.dashboard.opendatahub.io \
           datasciencepipelinesapplications.datasciencepipelinesapplications.opendatahub.io; do
  oc get crd "${crd}" --no-headers 2>/dev/null \
    && echo "  [OK] ${crd}" || echo "  [MISSING] ${crd}"
done

# ArgoCD 관리 현황
echo ""
echo "=== ArgoCD Applications ==="
oc get application -n openshift-gitops --no-headers 2>/dev/null | \
  awk '{print "  " $1 ": " $3}'
```

```
[화면에 보여줄 것]
1. CRD 목록 — InferenceService, ServingRuntime 등 K8s 표준 리소스
2. ArgoCD Dashboard — Git 기반 선언적 관리
3. YAML 예시 — kubectl apply 가능
```

**확인**: RHOAI 리소스가 K8s CRD이며, ArgoCD/GitOps로 관리 가능

---

## 확인 (Verification)

| # | 검증 기준 | 기대값 | 실측값 |
|---|----------|--------|--------|
| V-45 | LDAP 로그인 성공 | `oc whoami` = dev-user1 | |
| V-46 | AD 그룹 동기화 | dev-team, ops-team 그룹 존재 | |
| V-44 | RBAC 3단계 격리 | admin=yes, edit=yes, view=read-only | |
| V-44b | DS 삭제 거부 | `can-i delete` = no | |
| V-14 | HardwareProfile CR | Dashboard 드롭다운 반영 | |
| V-15 | ResourceQuota 적용 | GPU 쿼터 초과 시 거부 | |
| V-16 | K8s 네이티브 | InferenceService CRD 존재 | |
| V-68 | RHOAI Dashboard | HTTP 200 (웹 접근) | |
| V-69 | CLI 접근 | `oc get isvc` 정상 | |
| V-70 | REST API 접근 | JSON 응답 정상 | |

---

## 이번 시연에서 확인된 핵심 가치

- **기존 AD/LDAP 인프라 100% 재활용**: 별도 계정 시스템 없이 기존 조직도가 그대로 AI 플랫폼 권한에 반영됩니다. 퇴사자 AD 비활성화 시 AI 플랫폼 접근도 즉시 차단됩니다.
- **3단계 RBAC으로 보안 감사 대응**: admin/edit/view 역할이 K8s 네이티브 RoleBinding으로 강제됩니다. ISO 27001, ISMS-P 감사 시 권한 분리 증적을 즉시 제출할 수 있습니다.
- **ResourceQuota로 GPU 자원 거버넌스**: 팀별 GPU 상한선이 하드웨어 수준에서 강제되어, 특정 팀의 자원 독점이 구조적으로 불가능합니다.
- **K8s 네이티브 = 벤더 독립**: 모든 리소스가 CRD이므로 kubectl, ArgoCD, Terraform 등 기존 IaC 도구와 100% 호환됩니다. 벤더 종속(lock-in) 위험이 없습니다.

---

## 추천 사항

1. **AD 연동 시 TLS 사용**: PoC에서는 `insecure: true`를 사용했지만, 운영 환경에서는 반드시 LDAPS (636 포트) + CA 인증서를 구성하십시오.
2. **Group Sync CronJob 자동화**: `oc adm groups sync`를 CronJob으로 등록하여 AD 그룹 변경을 15분 간격으로 자동 반영하십시오.
3. **HardwareProfile 표준화**: 조직 내 GPU 할당 프리셋을 3~5개로 표준화하면 (Small/Medium/Large/XLarge), 자원 요청 편차를 줄이고 운영 예측 가능성이 높아집니다.
4. **ResourceQuota + Kueue 병행**: ResourceQuota는 상한선을 강제하고, Kueue는 대기열 기반 공정 스케줄링을 제공합니다. S8(멀티테넌트) 시나리오에서 상세히 다룹니다.
5. **감사 로그 보존**: OCP Audit Log를 외부 SIEM(Splunk, ELK)으로 전송하여 90일 이상 보존하십시오. 규정 준수 감사에 필수적입니다.
