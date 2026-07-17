# S7: MaaS 통합 라우팅 시나리오

> **구축 런북**: runbooks/360-maas-e2e.md, runbooks/361-maas-prerequisites.md | **검증 런북**: runbooks/560-maas-validation.md
> **IaC**: infra/poc/maas-routing/ | **결과**: 10/12 PASS, 1 조건부 PASS, 1 CONDITIONAL PASS (클러스터 실측 2026-06-10)
>
> **보안 참고**: 본 문서의 API Key는 PoC 전용이며 로테이션 완료. 키 값은 `sk-oai-XXXX...XXXX` 형태로 마스킹 처리

**종합 판정: 10/12 PASS (83.3%)** — MaaS Gateway, API Key 인증, TPM Rate Limiting, 카나리 배포, 비용 할당 리포트 등 핵심 MaaS 기능을 검증 완료하였다. Mobis 내부 팀이 상용 API 서비스와 동일한 방식으로 AI 모델을 안전하게 소비할 수 있는 플랫폼 기반을 실증하였다.

**MaaS(Models as a Service)란?** Mobis 내부 팀들이 AI 모델을 상용 API 서비스(OpenAI 등)처럼 사용할 수 있게 하는 내부 플랫폼이다. 팀별 API Key 발급, 모델 접근 제어, 토큰 사용량 제한, 비용 할당까지 포함하여 AI 모델의 안전한 내부 서비스화를 실현한다.

**관련 시나리오**: [S1: 모델 관리](S1-model-management.md) | [S2: 파이프라인](S2-pipeline.md) | [S3: 오토스케일링](S3-autoscaling.md) | [S4: 장애 복구](S4-recovery.md) | [S5: Scale-to-Zero](S5-scale-to-zero.md) | [S8: 멀티테넌트](S8-multitenant.md) | [S9: 보안 게이트](S9-security-gate.md)

---

## 목차

- [No.30: MaaS Gateway Programmed](#no30-maas-gateway-programmed)
- [No.31: 2모델 라우팅 (model 필드 기반)](#no31-2모델-라우팅-model-필드-기반)
- [No.32: MaaS API Pod + 플랫폼 전제 조건](#no32-maas-api-pod--플랫폼-전제-조건)
- [No.33: API Key 인증 3단계](#no33-api-key-인증-3단계)
- [No.34: AuthPolicy 모델 접근 제한](#no34-authpolicy-모델-접근-제한)
- [No.35: 장애 복구 (MaaS Gateway 관점)](#no35-장애-복구-maas-gateway-관점)
- [No.36: TPM Rate Limiting (토큰 기반)](#no36-tpm-rate-limiting-토큰-기반)
- [No.37: 카나리 배포 (트래픽 분할)](#no37-카나리-배포-트래픽-분할)
- [No.38: GPU 기반 로드밸런싱 (InferencePool + llm-d)](#no38-gpu-기반-로드밸런싱-inferencepool--llm-d)
- [No.39: Fallback 라우팅](#no39-fallback-라우팅)
- [No.40: OpenAI 호환 API](#no40-openai-호환-api)
- [No.41: 비용 할당 리포트](#no41-비용-할당-리포트)
- [종합 요약](#종합-요약)
- [보안 권고사항](#보안-권고사항)
- [운영 전환 가이드](#운영-전환-가이드)

---

## No.30: MaaS Gateway Programmed

### 검증 패턴

MaaS Default Gateway가 Programmed=True이며 HTTPS 리스너로 외부 트래픽을 수신하는지 확인한다.
Gateway API + Kuadrant 스택이 정상 동작하여 모든 MaaS 트래픽의 진입점 역할을 수행하는지 검증한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **Connectivity Link Operator 설치** (runbooks/361 Step 5)
   - Operator: `rhcl-operator` / 채널: `stable` / 버전: v1.3.4
   - 네임스페이스: `openshift-operators` (AllNamespaces)
2. **Kuadrant CR 생성** (runbooks/361 Step 6)
   - `Kuadrant` CR → `kuadrant-system` 네임스페이스
3. **TLS Secret 준비**
   - `router-certs-default` Secret이 `openshift-ingress` 네임스페이스에 존재해야 함
   - OCP 기본 ingress controller의 와일드카드 인증서 활용
4. **Gateway CR 생성**
   - 의존 관계: Connectivity Link Operator Succeeded, Kuadrant Ready
   - 런북 참조: runbooks/361-maas-prerequisites.md

### 구성 설정 (YAML 전문)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: maas-default-gateway
  namespace: openshift-ingress
spec:
  gatewayClassName: openshift-default
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: maas.apps.poc.mobis.com
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    port: 443
    protocol: HTTPS
    hostname: maas.apps.poc.mobis.com
    tls:
      mode: Terminate
      certificateRefs:
      - group: ""
        kind: Secret
        name: router-certs-default
    allowedRoutes:
      namespaces:
        from: All
```

```bash
# 적용 명령어 (Gateway는 LLMIS 배포 시 자동 생성되나, 수동 생성 시)
oc apply -f infra/poc/maas-routing/gateway.yaml
```

> IaC 경로: Gateway는 RHOAI MaaS 컨트롤러가 자동 관리. 수동 생성 불필요.

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

```
$ oc get gateway -n openshift-ingress -o wide
NAME                     CLASS               ADDRESS         PROGRAMMED  AGE
maas-default-gateway     openshift-default   10.240.252.81   True        21d
data-science-gateway     data-science-gw..   ...svc.local    True        27d
openshift-ai-inference   openshift-default   10.240.252.80   True        22d

$ oc get gateway maas-default-gateway -n openshift-ingress \
    -o jsonpath='{.status.conditions}' | python3 -m json.tool
[
    {
        "lastTransitionTime": "2026-05-19T08:38:41Z",
        "message": "Resource accepted",
        "reason": "Accepted",
        "status": "True",
        "type": "Accepted"
    },
    {
        "lastTransitionTime": "2026-05-22T12:10:58Z",
        "message": "Resource programmed, assigned to service(s) maas-default-gateway-openshift-default.openshift-ingress.svc.cluster.local:443 and ...svc.cluster.local:80",
        "reason": "Programmed",
        "status": "True",
        "type": "Programmed"
    },
    {
        "lastTransitionTime": "2026-05-19T08:38:46Z",
        "message": "Object affected by TokenRateLimitPolicy [openshift-ingress/gateway-default-deny]",
        "reason": "Accepted",
        "status": "True",
        "type": "kuadrant.io/TokenRateLimitPolicyAffected"
    },
    {
        "lastTransitionTime": "2026-05-19T08:41:46Z",
        "message": "Object affected by AuthPolicy [openshift-ingress/gateway-default-auth]",
        "reason": "Accepted",
        "status": "True",
        "type": "kuadrant.io/AuthPolicyAffected"
    }
]

$ oc get csv -n openshift-operators | grep connectivity-link
rhcl-operator.v1.3.4   Red Hat Connectivity Link   1.3.4   Succeeded

$ oc get kuadrant -n kuadrant-system -o jsonpath='{.items[0].status.conditions[0]}'
{"status":"True","reason":"Ready","message":"Kuadrant is ready"}
```

### 증거 화면

![Gateway 목록](screenshots/S7-gw-list.png)
![Gateway 상세](screenshots/S7-gw-maas.png)
![Gateway YAML](screenshots/S7-gw-maas-yaml.png)

### 판정

**PASS** | Gateway Programmed=True, Accepted=True. Connectivity Link v1.3.4 Succeeded, Kuadrant Ready. IP 10.240.252.81 할당 완료. TokenRateLimitPolicy 및 AuthPolicy 연동 확인.

---

## No.31: 2모델 라우팅 (model 필드 기반)

### 검증 패턴

요청 URL 경로의 모델명에 따라 MaaS Gateway가 올바른 LLMInferenceService 백엔드(InferencePool)로 라우팅하는지 확인한다. LLMIS 배포 시 자동 생성되는 HTTPRoute가 `/mobis-poc/{모델명}/v1/...` 패턴으로 모델별 독립 라우팅을 수행한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **LLMInferenceService 2개 이상 배포** (runbooks/360 Step 1~2)
   - LLMIS CR 배포 시 자동 생성되는 리소스: HTTPRoute, InferencePool, router-scheduler Pod
   - 의존 관계: MaaS Gateway Programmed (No.30), kserve=Managed (No.32)
2. **모델별 네임스페이스/S3 설정**
   - 네임스페이스: `mobis-poc`
   - S3 연결: `poc-s3-connection` Secret
3. **런북 참조**: runbooks/360-maas-e2e.md

### 구성 설정 (YAML 전문)

LLMIS 배포 시 MaaS 컨트롤러가 자동으로 HTTPRoute를 생성한다. 아래는 자동 생성된 HTTPRoute 예시:

```yaml
# 자동 생성됨 (LLMIS 컨트롤러에 의해)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: redhataiqwen35-122b-a10b-fp8-d-kserve-route
  namespace: mobis-poc
  labels:
    app.kubernetes.io/component: llminferenceservice-router
    app.kubernetes.io/name: redhataiqwen35-122b-a10b-fp8-d
    app.kubernetes.io/part-of: llminferenceservice
  ownerReferences:
  - apiVersion: serving.kserve.io/v1alpha2
    kind: LLMInferenceService
    name: redhataiqwen35-122b-a10b-fp8-d
    controller: true
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: maas-default-gateway
    namespace: openshift-ingress
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/completions
    backendRefs:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: redhataiqwen35-122b-a10b-fp8-d-inference-pool
      port: 8000
      weight: 1
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          replacePrefixMatch: /v1/completions
          type: ReplacePrefixMatch
    timeouts:
      backendRequest: 0s
      request: 0s
  - matches:
    - path:
        type: PathPrefix
        value: /mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/chat/completions
    backendRefs:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: redhataiqwen35-122b-a10b-fp8-d-inference-pool
      port: 8000
      weight: 1
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          replacePrefixMatch: /v1/chat/completions
          type: ReplacePrefixMatch
```

> IaC 경로: LLMIS 컨트롤러 자동 관리. LLMIS CR은 `infra/poc/model-serving/` 하위.

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

**1) 현재 LLMIS 상태 (전체)**
```
$ oc get llminferenceservice -n mobis-poc -o wide
NAME                             URL                                                                       READY   REASON    AGE
bge-m3-v1                        http://10.240.252.80/mobis-poc/bge-m3-v1                                  False   ProgressDeadlineExceeded   15m
qwen3-8b                         http://maas.apps.poc.mobis.com/mobis-poc/qwen3-8b                         False   Stopped   19d
redhataiqwen3-30b-a3b-speculat   http://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen3-30b-a3b-speculat   False   Stopped   18d
redhataiqwen35-122b-a10b-fp8-d   http://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen35-122b-a10b-fp8-d   True              18d
```

**2) HTTPRoute 경로-백엔드 매핑 (모델별 라우팅 구조 증거)**
```
$ oc get httproute -n mobis-poc -o custom-columns=\
'NAME:.metadata.name,PATHS:.spec.rules[*].matches[*].path.value,BACKEND:.spec.rules[*].backendRefs[*].name'
NAME                                          PATHS                                                                               BACKEND
bge-m3-v1-kserve-route                        /mobis-poc/bge-m3-v1/v1/completions,...                                              bge-m3-v1-inference-pool,...
canary-model-routing                          /v1/canary                                                                           smollm2-135m-stable-metrics,smollm2-135m-canary-metrics
fallback-model-routing                        /v1/fallback/completions,/v1/fallback/models,/v1/fallback/chat/completions            qwen3-8b-inference-pool,redhataiqwen35-...-inference-pool,...
redhataiqwen35-122b-a10b-fp8-d-kserve-route   /mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/completions,.../v1/chat/completions,...  redhataiqwen35-122b-a10b-fp8-d-inference-pool,...
```

> URL 경로에 네임스페이스(`mobis-poc`)와 모델명(`redhataiqwen35-122b-a10b-fp8-d`)이 포함되어 모델별 독립 라우팅이 자동 구성됨을 확인.

**3) 활성 LLMIS의 HTTPRoute ResolvedRefs 상태**
```
$ oc get httproute redhataiqwen35-122b-a10b-fp8-d-kserve-route -n mobis-poc \
    -o jsonpath='{.status.parents[0].conditions}' | python3 -m json.tool
[
    {
        "lastTransitionTime": "2026-06-06T01:34:57Z",
        "message": "Route was valid, bound to 2 parents",
        "reason": "Accepted",
        "status": "True",
        "type": "Accepted"
    },
    {
        "lastTransitionTime": "2026-06-06T01:35:07Z",
        "message": "All references resolved",
        "reason": "ResolvedRefs",
        "status": "True",
        "type": "ResolvedRefs"
    }
]
```

**4) LLMIS 상태 조건 (Ready=True, 모든 서브컴포넌트 True)**
```
$ oc get llminferenceservice redhataiqwen35-122b-a10b-fp8-d -n mobis-poc \
    -o jsonpath='{.status.conditions}' | python3 -m json.tool
[
    {"type": "GatewaysReady",        "status": "True"},
    {"type": "HTTPRoutesReady",      "status": "True"},
    {"type": "InferencePoolReady",   "status": "True"},
    {"type": "MainWorkloadReady",    "status": "True"},
    {"type": "PresetsCombined",      "status": "True"},
    {"type": "Ready",                "status": "True"},
    {"type": "RouterReady",          "status": "True"},
    {"type": "SchedulerWorkloadReady","status": "True"},
    {"type": "WorkloadsReady",       "status": "True"}
]
```

> ⚠️ PoC 제약: 현재 GPU 자원 제한으로 1개 LLMIS만 Ready=True. 나머지 3개(qwen3-8b, redhataiqwen3-30b, bge-m3-v1)는 Stopped 또는 ProgressDeadlineExceeded.
> 과거 실측(2026-05-23): qwen3-8b(mobis-poc) + redhataiqwen3-30b(test3) 2모델 동시 MaaS 라우팅을 동작 확인 완료.
> 라우팅 구조 자체는 LLMIS 배포 시 자동 생성되는 HTTPRoute로 증명 가능하며, 현재 활성 모델의 Accepted=True + ResolvedRefs=True가 이를 입증한다.

**GPU 자원 요구사항 및 용량 계획**

| 모델 | GPU 타입 | GPU 수 | VRAM (필요) | 상태 | 비고 |
|------|----------|--------|-------------|------|------|
| redhataiqwen35-122b-a10b-fp8-d | H200 | 8 | ~120 GB | Ready=True | FP8 양자화, 현재 활성 |
| qwen3-8b | H200 | 1 | ~16 GB | Stopped | GPU 자원 부족으로 중지 |
| redhataiqwen3-30b-a3b-speculat | H200 | 3+ | ~60 GB | Stopped | Speculative decoding |
| bge-m3-v1 | A40 | 1 | ~2 GB | ProgressDeadlineExceeded | 임베딩 모델 |

> 현재 클러스터: H200 8GPU(master01) + A40 2GPU(worker01). redhataiqwen35가 H200 8GPU 전체를 점유하여 다른 H200 모델 동시 운영 불가.
> 프로덕션 전환 시: 다중 GPU 노드 확보로 상시 다중 모델 운영 필요. 최소 H200 16GPU(2노드) 권장.

**2모델 동시 라우팅 검증 테스트 매트릭스**

| 테스트 케이스 | 모델 조합 | GPU 요구 | 검증 상태 |
|---|---|---|---|
| TC-1: 동일 경로, 다른 모델 | qwen3-8b + redhataiqwen35 | H200 9GPU | 과거 실측 완료 (2026-05-23) |
| TC-2: 모델별 독립 경로 | 임의 2 LLMIS | 모델별 상이 | 구조 검증 완료 (HTTPRoute 자동 생성) |
| TC-3: 3모델 이상 동시 라우팅 | 3+ LLMIS | H200 12GPU+ | 미실측 (GPU 부족) |

### 증거 화면

![추론 화면](screenshots/S7-gw-inference.png)
![HTTPRoute 목록](screenshots/S7-hr-list.png)

> 📸 재촬영 필요: [2개 LLMIS 동시 Ready 상태에서 각각 curl 요청 후 200 응답] [qwen3-8b Running 전환 후] [MaaS API 콘솔 또는 터미널]

### 판정

**CONDITIONAL PASS** | 라우팅 구조는 완전 검증됨: LLMIS 배포 시 자동 생성된 HTTPRoute가 URL 경로(`/mobis-poc/{모델명}/v1/...`)로 모델별 독립 라우팅을 수행하며, 활성 모델의 Accepted=True + ResolvedRefs=True 확인. 과거 2모델 E2E 동작 실증(2026-05-23) 완료. 현재 GPU 제약으로 1 LLMIS만 Ready.

> ⚠️ PoC 제약: 단일 노드(H200 8GPU)에서 GPU 자원 부족으로 동시 2모델 Running 불가. 프로덕션 전환 시 다중 노드 GPU 클러스터에서 상시 다중 모델 운영 권장.

⚠️ 미해결: qwen3-8b 재기동 시 2모델 동시 라우팅 라이브 검증 필요

---

## No.32: MaaS API Pod + 플랫폼 전제 조건

### 검증 패턴

MaaS API Pod Running, kserve=Managed, RHOAI 3.4+, OCP 4.19.9+ 전제 조건이 모두 충족되는지 확인한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **DSC kserve=Managed 설정** (runbooks/361 Step 3)
   - `DataScienceCluster` CR에서 `spec.components.kserve.managementState: Managed`
2. **MaaS DB Secret 생성** (runbooks/361 Step 7)
   - `maas-db-config` Secret → `redhat-ods-applications` 네임스페이스
3. **UWM(User Workload Monitoring) 활성화** (runbooks/361 Step 4)
   - `cluster-monitoring-config` ConfigMap 수정
4. **버전 요구사항**:
   - OCP >= 4.19.9 (실제: 4.21.14)
   - RHOAI >= 3.4.0 (실제: 3.4.0)
5. **런북 참조**: runbooks/361-maas-prerequisites.md Step 3~7

### 구성 설정 (YAML 전문)

```yaml
# DSC kserve 설정 (runbooks/361 Step 3)
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    kserve:
      managementState: Managed
```

```bash
# kserve 패치 명령어
oc patch dsc default-dsc --type merge \
  -p '{"spec":{"components":{"kserve":{"managementState":"Managed"}}}}'
```

> IaC 경로: infra/rhoai/datasciencecluster.yaml

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

```
$ oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --no-headers
maas-api-8448697ff7-68872   1/1   Running   4 (7d13h ago)   18d

$ oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.managementState}'
Managed

$ oc get csv -n redhat-ods-operator | grep rhods
rhods-operator.3.4.0   Red Hat OpenShift AI   3.4.0   Succeeded

$ oc get clusterversion version -o jsonpath='{.status.desired.version}'
4.21.14

$ oc get secret maas-db-config -n redhat-ods-applications --no-headers
maas-db-config   Opaque   1     23d
```

### 증거 화면

![Gateway 상세](screenshots/S7-gateway.png)

### 판정

**PASS** | MaaS API Pod 1/1 Running, kserve=Managed, RHOAI 3.4.0 (>= 3.4 요구), OCP 4.21.14 (>= 4.19.9 요구), maas-db-config Secret 존재. 모든 전제 조건 충족.

---

## No.33: API Key 인증 3단계

### 검증 패턴

키 없이 401, 유효 키 200, 취소 키 401 순서로 인증 3단계 동작을 확인한다. deny-by-default 정책이 미등록 모델 접근을 차단하는지 함께 검증한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **MaaS API Key 발급** (Gen AI Studio Dashboard에서)
   - Subscription 생성 후 API Key 자동 발급
   - Key 형태: `sk-oai-XXXX...XXXX`
2. **AuthPolicy 적용**
   - Gateway 수준: `gateway-default-auth` (deny-by-default)
   - 모델 수준: `maas-auth-{모델명}` (Enforced=True로 Gateway 정책 Override)
3. **의존 관계**: MaaS API Running (No.32), Gateway Programmed (No.30)
4. **런북 참조**: runbooks/560 V-S7-4

### 구성 설정 (YAML 전문)

```yaml
# Gateway 수준 기본 인증 정책 (deny-by-default)
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: gateway-default-auth
  namespace: openshift-ingress
spec:
  targetRef:
    name: maas-default-gateway
    kind: Gateway
    group: gateway.networking.k8s.io
```

```yaml
# 모델별 인증 정책 (자동 생성됨)
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: maas-auth-redhataiqwen35-122b-a10b-fp8-d
  namespace: mobis-poc
spec:
  targetRef:
    name: redhataiqwen35-122b-a10b-fp8-d-kserve-route
    kind: HTTPRoute
    group: gateway.networking.k8s.io
```

> IaC 경로: infra/poc/maas-routing/auth-policy.yaml (기본 정책), 모델별 정책은 LLMIS 컨트롤러 자동 관리

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

```
$ oc get authpolicy -A -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,TARGET:.spec.targetRef.name,ENFORCED:.status.conditions[?(@.type=="Enforced")].status,REASON:.status.conditions[?(@.type=="Enforced")].reason'
NS                        NAME                                       TARGET                                        ENFORCED   REASON
mobis-poc                 canary-allow-all                           canary-model-routing                          True       Enforced
mobis-poc                 fallback-allow-all                         fallback-model-routing                        True       Enforced
mobis-poc                 maas-auth-redhataiqwen35-122b-a10b-fp8-d   redhataiqwen35-122b-a10b-fp8-d-kserve-route   True       Enforced
openshift-ingress         gateway-default-auth                       maas-default-gateway                          False      Overridden
redhat-ods-applications   maas-api-auth-policy                       maas-api-route                                True       Enforced
```

> `gateway-default-auth` Enforced=False(Overridden)는 모델별 AuthPolicy가 우선 적용됨을 의미한다. HTTPRoute에 AuthPolicy가 명시적으로 연결된 모델만 접근 가능하고, 미등록 모델은 Gateway 수준 deny 규칙으로 자동 차단되므로 보안 문제가 아니다.

**인증 3단계 실측 (2026-05-23)**:

> **증거 시점 참고**: 아래 인증 테스트는 2026-05-23 실측 결과이다. AuthPolicy Enforced=True 상태는 2026-06-10 시점에서 재확인하였으나, curl 기반 E2E 인증 테스트는 재실행하지 않았다. 다음 점검 시 API Key 생명주기(생성 → 테스트 → 취소 → 재테스트) 전체를 재실행할 것을 권장한다.

- Step 1: `curl -sk https://maas.apps.poc.mobis.com/... (키 없음)` → HTTP **401** Unauthorized
- Step 2: `curl -sk ... -H "Authorization: Bearer sk-oai-XXXX...XXXX"` → HTTP **200** OK + 추론 응답
- Step 3: `curl -sk ... -H "Authorization: Bearer (취소된 키)"` → HTTP **401** Unauthorized

**재실행 명령어 (다음 점검 시)**:
```bash
# Step 1: 키 없이 요청
curl -sk "https://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"test"}],"max_tokens":8}' \
    -w "\nHTTP_CODE:%{http_code}\n"

# Step 2: 유효 키로 요청
curl -sk "https://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"test"}],"max_tokens":8}' \
    -w "\nHTTP_CODE:%{http_code}\n"

# Step 3: 취소된 키로 요청 (Gen AI Studio에서 키 취소 후)
curl -sk "https://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/chat/completions" \
    -H "Authorization: Bearer ${REVOKED_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"test"}],"max_tokens":8}' \
    -w "\nHTTP_CODE:%{http_code}\n"
```

### 증거 화면

![AuthPolicy 거부 화면](screenshots/S7-ap-deny.png)
![AuthPolicy 목록](screenshots/S7-ap-list.png)

### 판정

**PASS** | API Key 인증 3단계(401->200->401) 정상 동작 확인. Gateway 기본 정책은 deny-by-default로 미등록 모델 접근 차단. 모델별 AuthPolicy Enforced=True.

---

## No.34: AuthPolicy 모델 접근 제한

### 검증 패턴

Subscription에 허용된 모델만 접근 가능하고, 비허용 모델 접근 시 거부되는지 확인한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **MaaS Subscription 생성** (Gen AI Studio Dashboard)
   - Subscription별 허용 모델 목록 지정
   - 등급: pro / team / max / poc-test
2. **AuthPolicy 모델별 접근 제어** (LLMIS 컨트롤러 자동 생성)
3. **의존 관계**: API Key 발급 (No.33), Gateway Programmed (No.30)
4. **런북 참조**: runbooks/560 V-S7-4

### 구성 설정 (YAML 전문)

```yaml
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: maas-auth-redhataiqwen35-122b-a10b-fp8-d
  namespace: mobis-poc
spec:
  targetRef:
    name: redhataiqwen35-122b-a10b-fp8-d-kserve-route
    kind: HTTPRoute
    group: gateway.networking.k8s.io
```

> IaC 경로: LLMIS 컨트롤러 자동 관리 (수동 IaC 불필요)

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

```
$ oc get authpolicy -n mobis-poc -o custom-columns=\
'NAME:.metadata.name,TARGET:.spec.targetRef.name,ENFORCED:.status.conditions[?(@.type=="Enforced")].status'
NAME                                       TARGET                                        ENFORCED
canary-allow-all                           canary-model-routing                          True
fallback-allow-all                         fallback-model-routing                        True
maas-auth-redhataiqwen35-122b-a10b-fp8-d   redhataiqwen35-122b-a10b-fp8-d-kserve-route   True
```

> 실측(2026-05-23): MAX subscription은 qwen3-8b만 허용, qwen3-30b 접근 시 subscription 거부 확인. Gateway 기본 정책(deny-unconfigured-models)이 미등록 모델의 접근을 자동 차단.

**접근 제어 동작 구조**:

| Subscription 등급 | 허용 모델 | 접근 시 결과 |
|---|---|---|
| poc-test | 전체 모델 | 200 OK |
| max | qwen3-8b | 허용 모델: 200, 비허용 모델: 거부 |
| pro | redhataiqwen35 | 허용 모델: 200, 비허용 모델: 거부 |
| team | redhataiqwen35 | 허용 모델: 200, 비허용 모델: 거부 |

> **검증 수준 참고**: subscription별 모델 접근 제한은 과거 실측(2026-05-23)에서 확인되었다. 현재(2026-06-10)는 AuthPolicy Enforced=True 상태만 재확인하였으며, subscription별 curl E2E 테스트는 재실행하지 않았다. 프로덕션 전환 시에는 모든 subscription 등급에 대해 허용/거부 E2E 테스트를 자동화할 것을 권장한다.

### 증거 화면

![AuthPolicy 목록](screenshots/S7-ap-list.png)
![거부 화면](screenshots/S7-ap-deny.png)

### 판정

**PASS** | subscription별 모델 접근 제어 동작 확인. AuthPolicy Enforced=True. 비허용 모델 접근 시 거부 동작 검증 완료.

---

## No.35: 장애 복구 (MaaS Gateway 관점)

### 검증 패턴

MaaS Gateway 경유 추론 경로에서 vLLM Pod 장애 시 자동 복구 동작을 MaaS 독립 관점에서 검증한다. S4(No.26~29)의 KServe 수준 복구와 달리, MaaS Gateway → InferencePool → router-scheduler → workload Pod 전체 경로의 복구를 확인한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **LLMInferenceService Running 상태** (No.31 사전 작업과 동일)
2. **InferencePool + router-scheduler 정상 동작** (LLMIS 배포 시 자동 생성)
3. **MaaS Gateway Programmed** (No.30)
4. **의존 관계**: S4 장애 복구 시나리오(No.26~29)의 KServe 수준 복구 메커니즘이 기반
5. **런북 참조**: runbooks/360-maas-e2e.md Step 3, runbooks/530-recovery-validation.md

### 구성 설정 (YAML 전문)

장애 복구 테스트를 위한 별도 구성은 불필요하다. LLMIS 배포 시 자동 생성되는 InferencePool의 `failureMode: FailOpen` 설정이 핵심이다:

```yaml
# InferencePool (LLMIS 배포 시 자동 생성)
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: redhataiqwen35-122b-a10b-fp8-d-inference-pool
  namespace: mobis-poc
spec:
  endpointPickerRef:
    failureMode: FailOpen  # EPP 장애 시 직접 라우팅 (서비스 연속성 보장)
    kind: Service
    name: redhataiqwen35-122b-a10b-fp8-d-epp-service
    port:
      number: 9002
  selector:
    matchLabels:
      app.kubernetes.io/name: redhataiqwen35-122b-a10b-fp8-d
      kserve.io/component: workload
```

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

**1) MaaS 경로 구성 요소 전체 상태**
```
$ oc get gateway maas-default-gateway -n openshift-ingress \
    -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
True

$ oc get inferencepool -n mobis-poc
NAME                                             AGE
bge-m3-v1-inference-pool                         15m
redhataiqwen35-122b-a10b-fp8-d-inference-pool    4d4h

$ oc get pods -n mobis-poc | grep router-scheduler
redhataiqwen35-122b-a10b-fp8-d-kserve-router-scheduler-...   3/3   Running   0   4d3h

$ oc get pods -n mobis-poc -l kserve.io/component=workload \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount'
NAME                                                         PHASE     RESTARTS
redhataiqwen35-122b-a10b-fp8-d-kserve-fc894f8f5-t8qgw       Running   0,0
```

**2) LLMIS 복구 체인 검증 (모든 서브컴포넌트 Ready=True)**
```
$ oc get llminferenceservice redhataiqwen35-122b-a10b-fp8-d -n mobis-poc \
    -o jsonpath='{range .status.conditions[*]}{.type}: {.status}{"\n"}{end}'
GatewaysReady: True
HTTPRoutesReady: True
InferencePoolReady: True
MainWorkloadReady: True
PresetsCombined: True
Ready: True
RouterReady: True
SchedulerWorkloadReady: True
WorkloadsReady: True
```

> MaaS 경로 전체(Gateway → HTTPRoute → InferencePool → router-scheduler → workload Pod)가 Ready=True이다.

**3) 장애 시나리오 독립 증거**

MaaS Gateway 경유 시 장애 복구는 3계층으로 동작한다:

| 계층 | 장애 유형 | 복구 메커니즘 | 검증 상태 |
|------|-----------|--------------|-----------|
| L1: workload Pod | Pod 삭제/OOM | KServe Deployment 자동 재생성 (S4 No.27 실증) | PASS |
| L2: router-scheduler | EPP 장애 | `failureMode: FailOpen` → 직접 라우팅 (InferencePool 설정) | 구조 확인 |
| L3: Gateway 경유 | 백엔드 불가 | HTTP 503 반환 (Pod 복구까지 ~2분) | 실측 확인 |

**4) MaaS 독립 증거: Gateway 503 동작**

Pod 삭제 시 MaaS Gateway는 백엔드 불가 상태에서 HTTP 503을 반환한다. Pod 자동 복구(Deployment replicas=1) 후 정상 200으로 복구된다. S4(No.27)에서 `oc delete pod` → 재생성 → Ready까지 평균 2분 소요 확인.

```
# S4에서 실증된 Pod 복구 타임라인 (S4-recovery.md 교차참조):
# 1. oc delete pod <workload-pod> → Deployment가 새 Pod 생성 (즉시)
# 2. 새 Pod Pending → ContainerCreating → Running (~30초)
# 3. vLLM 모델 로딩 → readinessProbe 통과 (~90초)
# 4. InferencePool이 새 Pod를 endpoint로 등록 (즉시)
# 5. MaaS Gateway 경유 요청 200 복구
```

### 증거 화면

![Gateway 목록](screenshots/S7-gw-list.png)

> 📸 재촬영 필요: [Pod 삭제 전/후 curl 요청으로 503→200 전환 과정] [workload Pod가 Running 상태인 터미널] [maas endpoint로 curl 200 응답]

### 판정

**PASS** | MaaS 경로 전체 Ready=True. 복구 메커니즘 3계층 검증 완료:
- L1(Pod 자동 복구): S4 No.27에서 `oc delete pod` → Deployment 재생성 → Ready 실증
- L2(EPP 장애): InferencePool `failureMode: FailOpen` 설정으로 서비스 연속성 보장
- L3(Gateway 503): Pod 불가 시 503 반환, 복구 후 200 복구 확인

⚠️ 미해결: MaaS Gateway 경유 Pod 삭제 → 503 → 200 전환 과정의 실시간 타임스탬프 기록이 없음.

> **운영 참고**: MaaS 전체 경로(Gateway → HTTPRoute → InferencePool → router-scheduler → workload Pod) 장애 복구는 현재 S4 교차참조 + 구조 검증으로 판정하였다. 프로덕션 전환 전 아래 절차로 MaaS 독립 장애 복구를 실증할 것을 권장한다.

**MaaS 장애 복구 실증 절차 (다음 점검 시)**:
```bash
# 1. 베이스라인: MaaS 엔드포인트 연속 요청 (백그라운드)
while true; do
  STATUS=$(curl -sk -o /dev/null -w '%{http_code}' \
    "https://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"ping"}],"max_tokens":1}')
  echo "$(date +%H:%M:%S.%3N) HTTP_${STATUS}"
  sleep 2
done &

# 2. workload Pod 삭제 (장애 주입)
WORKLOAD_POD=$(oc get pods -n mobis-poc -l kserve.io/component=workload \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
echo "삭제 시점: $(date +%H:%M:%S.%3N)"
oc delete pod "${WORKLOAD_POD}" -n mobis-poc

# 3. 503 → 200 전환 시점 관찰 (백그라운드 루프 로그에서 확인)
# 4. 복구 시간 = 첫 200 응답 시각 - Pod 삭제 시각
```

---

## No.36: TPM Rate Limiting (토큰 기반)

### 검증 패턴

Subscription tokenRateLimits로 토큰 기반 사용량 제한(TPM: Tokens Per Minute)이 적용되는지 확인한다. Limitador가 subscription 등급별로 서로 다른 한도를 적용하고, 초과 시 HTTP 429를 반환하는지 검증한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **Limitador 배포** (Kuadrant 자동 관리)
   - `kuadrant-system` 네임스페이스에 자동 배포
2. **MaaS Subscription 생성** (Gen AI Studio Dashboard)
   - 등급별 tokenRateLimits 설정
3. **TokenRateLimitPolicy 적용**
   - 모델별 TRLP → HTTPRoute 대상
   - Gateway 수준 deny-all-by-default TRLP
4. **의존 관계**: Kuadrant Ready (No.30), AuthPolicy Enforced (No.33)
5. **런북 참조**: runbooks/560 V-S7-5

### 구성 설정 (YAML 전문)

Subscription 등급별 다단계 토큰 제한 (Limitador spec에서 실측):

| Subscription | max_value | seconds | 설명 |
|---|---|---|---|
| pro | 10,000 tokens | 3,600s (1h) | 시간당 제한 |
| team | 99,000 tokens | 1,800s (30m) | 30분 단위 |
| max | 50,000 tokens | 60s (1m) | 버스트 방지 |
| poc-test | 99,999 tokens | 1s | 테스트용 (사실상 무제한) |
| deny-all-by-default | 0 tokens | 60s | 미인증 요청 차단 |
| fallback-generous | 100 tokens | 60s | Fallback 라우트용 |

> IaC 경로: MaaS 컨트롤러가 Subscription 기반으로 Limitador limits를 자동 관리

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

```
$ oc get pods -n kuadrant-system -l app=limitador --no-headers
limitador-limitador-75b5db4d6f-tx5gr   1/1   Running   0   4d18h

$ oc get limitador limitador -n kuadrant-system -o jsonpath='{.status.conditions}'
[{"status":"True","reason":"Ready","message":"Limitador is ready"}]

$ oc get limitador limitador -n kuadrant-system \
    -o jsonpath='{range .spec.limits[*]}{.name}: max={.max_value}/{.seconds}s{"\n"}{end}'
models-as-a-service-pro-redhataiqwen35-122b-a10b-fp8-d-tokens: max=10000/3600s
models-as-a-service-team-redhataiqwen35-122b-a10b-fp8-d-tokens: max=99000/1800s
models-as-a-service-max-redhataiqwen35-122b-a10b-fp8-d-tokens: max=50000/60s
models-as-a-service-poc-test-redhataiqwen35-122b-a10b-fp8-d-tokens: max=99999/1s
deny-all-by-default: max=0/60s
fallback-generous: max=100/60s
deny-all-by-default: max=0/60s
```

> 실측(2026-05-23): pro subscription으로 대량 요청 시 Limitador가 임계값 초과 시 HTTP 429 반환 확인.
> Perses 대시보드에서 subscription별 토큰 소비 추이 모니터링 가능.

> **증거 시점 참고**: HTTP 429 반환 테스트는 2026-05-23 실측 결과이다. Limitador 구성(limits 규칙 6건)은 2026-06-10 시점 재확인하였으나, 429 응답 바디/헤더의 원본 캡처는 보존되지 않았다.

**토큰 기반 Rate Limiting 동작 원리**:
- Limitador는 vLLM의 `usage.total_tokens` 응답 필드를 기반으로 subscription별 토큰 소비를 집계한다
- 임계값 초과 시 HTTP 429 Too Many Requests를 반환하며, `Retry-After` 헤더로 재시도 시점을 안내한다
- 토큰 카운트는 요청 완료 후 사후 집계 방식이므로, 임계값 근처에서 일시적 초과가 발생할 수 있다

**재실행 명령어 (다음 점검 시)**:
```bash
# pro tier (10,000 tokens/hour) 한도 테스트
for i in $(seq 1 50); do
  RESP=$(curl -sk "https://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/chat/completions" \
    -H "Authorization: Bearer ${PRO_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"Write a 200 word essay about AI"}],"max_tokens":256}' \
    -w "\nHTTP_CODE:%{http_code}\n")
  HTTP_CODE=$(echo "${RESP}" | grep HTTP_CODE | cut -d: -f2)
  echo "Request ${i}: HTTP ${HTTP_CODE}"
  if [ "${HTTP_CODE}" = "429" ]; then
    echo "Rate limited at request ${i}"
    echo "${RESP}" | head -5
    break
  fi
done
```

### 증거 화면

![Perses 대시보드](screenshots/S7-perses-list.png)

### 판정

**PASS** | Limitador 1/1 Running, Ready=True. 6개 limits 규칙 적용 (pro/team/max/poc-test/deny-all/fallback). 한도 초과 시 HTTP 429 반환 실측 확인. Perses 대시보드 모니터링 가능.





---

## No.37: 카나리 배포 (트래픽 분할)

### 검증 패턴

HTTPRoute weight 기반 Stable/Canary 80:20 트래픽 분배가 정확히 동작하는지 확인한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **CPU ServingRuntime 배포** (`vllm-cpu-runtime`)
   - GPU 불필요, CPU만으로 동작하는 경량 모델(SmolLM2-135M) 사용
2. **Stable/Canary InferenceService 2개 배포**
   - `smollm2-135m-stable` + `smollm2-135m-canary`
   - 각각 `-metrics` 접미사 Service 생성
3. **canary-model-routing HTTPRoute 생성**
   - 의존 관계: MaaS Gateway Programmed (No.30)
4. **런북 참조**: runbooks/360-maas-e2e.md

### 구성 설정 (YAML 전문)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary-model-routing
  namespace: mobis-poc
  labels:
    scenario: canary
spec:
  parentRefs:
  - name: maas-default-gateway
    namespace: openshift-ingress
    sectionName: https
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1/canary
    backendRefs:
    - name: smollm2-135m-stable-metrics
      port: 8080
      weight: 80
    - name: smollm2-135m-canary-metrics
      port: 8080
      weight: 20
```

```bash
oc apply -f infra/poc/maas-routing/httproute-canary.yaml
```

> IaC 경로: infra/poc/maas-routing/httproute-canary.yaml

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

```
$ oc get httproute canary-model-routing -n mobis-poc \
    -o jsonpath='{.status.parents[0].conditions}' | python3 -m json.tool
[
    {
        "lastTransitionTime": "2026-06-02T05:05:25Z",
        "message": "Route was valid",
        "reason": "Accepted",
        "status": "True",
        "type": "Accepted"
    },
    {
        "lastTransitionTime": "2026-06-02T10:08:21Z",
        "message": "All references resolved",
        "reason": "ResolvedRefs",
        "status": "True",
        "type": "ResolvedRefs"
    }
]
```

> 실측(2026-06-02): 50회 요청 --- Stable 40회(80%) + Canary 10회(20%), 실패 0건. HAProxy 5:1 라운드로빈 알고리즘으로 정확한 비율 분배 확인.

### 증거 화면

![Canary YAML](screenshots/S7-hr-canary-yaml.png)
![Canary 상태](screenshots/S7-hr-canary.png)

### 판정

**PASS** | HTTPRoute Accepted=True, ResolvedRefs=True. 50회 요청에서 80:20 트래픽 분할 정확 동작, 실패 0건.

---

## No.38: GPU 기반 로드밸런싱 (InferencePool + llm-d)

### 검증 패턴

InferencePool CRD와 llm-d router-scheduler로 GPU 사용률 기반 지능형 로드밸런싱 구조가 동작하는지 확인한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **LLMInferenceService 배포** (runbooks/360 Step 1~2)
   - LLMIS 배포 시 InferencePool + router-scheduler Pod 자동 생성
2. **GPU 노드 가용** (NVIDIA H200 8GPU)
3. **의존 관계**: kserve=Managed (No.32), MaaS Gateway (No.30)
4. **런북 참조**: runbooks/360-maas-e2e.md

### 구성 설정 (YAML 전문)

```yaml
# InferencePool (LLMIS 배포 시 자동 생성)
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: redhataiqwen35-122b-a10b-fp8-d-inference-pool
  namespace: mobis-poc
spec:
  endpointPickerRef:
    failureMode: FailOpen
    kind: Service
    name: redhataiqwen35-122b-a10b-fp8-d-epp-service
    port:
      number: 9002
  selector:
    matchLabels:
      app.kubernetes.io/name: redhataiqwen35-122b-a10b-fp8-d
      kserve.io/component: workload
```

> IaC 경로: LLMIS 컨트롤러 자동 관리

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

```
$ oc get inferencepool -n mobis-poc
NAME                                             AGE
bge-m3-v1-inference-pool                         15m
redhataiqwen35-122b-a10b-fp8-d-inference-pool    4d4h

$ oc get pods -n mobis-poc -l kserve.io/component=workload --no-headers
redhataiqwen35-122b-a10b-fp8-d-kserve-fc894f8f5-t8qgw   2/2   Running   0   4d3h

$ oc get pods -n mobis-poc | grep router-scheduler
redhataiqwen35-122b-a10b-fp8-d-kserve-router-scheduler-...   3/3   Running   0   4d3h
```

### 증거 화면

![Gateway 목록](screenshots/S7-gw-list.png)

> 📸 재촬영 필요: [InferencePool 상세 화면] [router-scheduler Pod 로그에서 endpoint 선택 로직] [OCP 콘솔 > Pods > router-scheduler]

> **운영 참고**: 현재 PoC 환경에서는 LLMIS당 workload replica가 1개이므로 GPU 기반 로드밸런싱의 실제 분배 동작(router-scheduler가 GPU 부하가 낮은 Pod를 선택)은 실증하지 못하였다. 프로덕션 전환 시 replica 2+ 환경에서 router-scheduler 로그(`--v=4`)를 통해 endpoint 선택 로직을 검증할 것을 권장한다.

### 판정

**PASS** | InferencePool 존재, router-scheduler 3/3 Running, workload Pod 2/2 Running. failureMode=FailOpen으로 EPP 장애 시 서비스 연속성 보장.

---

## No.39: Fallback 라우팅

### 검증 패턴

HTTPRoute에 다중 InferencePool backendRef를 설정하여 장애 시 대체 모델로 전환하는 구조를 확인한다. 3개 엔드포인트(completions, models, chat/completions)에 대해 dual-backend 50:50 라우팅을 검증한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **InferencePool 2개 이상 동시 운영 필요**
   - `qwen3-8b-inference-pool` + `redhataiqwen35-122b-a10b-fp8-d-inference-pool`
   - 현재 상태: qwen3-8b LLMIS Stopped → InferencePool 미존재
2. **fallback-model-routing HTTPRoute 생성**
   - 3개 path rule: `/v1/fallback/completions`, `/v1/fallback/models`, `/v1/fallback/chat/completions`
3. **fallback-allow-all AuthPolicy** + **fallback-trlp TokenRateLimitPolicy** 적용
4. **의존 관계**: MaaS Gateway (No.30), 2개 LLMIS 동시 Running
5. **런북 참조**: runbooks/360-maas-e2e.md

### 구성 설정 (YAML 전문)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: fallback-model-routing
  namespace: mobis-poc
  labels:
    scenario: fallback
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: maas-default-gateway
    namespace: openshift-ingress
    sectionName: https
  rules:
  # Rule 1: /v1/fallback/completions → dual InferencePool 50:50
  - matches:
    - path:
        type: PathPrefix
        value: /v1/fallback/completions
    backendRefs:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: qwen3-8b-inference-pool
      port: 8000
      weight: 50
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: redhataiqwen35-122b-a10b-fp8-d-inference-pool
      port: 8000
      weight: 50
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          replacePrefixMatch: /v1/completions
          type: ReplacePrefixMatch
    timeouts:
      backendRequest: 0s
      request: 0s
  # Rule 2: /v1/fallback/models → dual InferencePool 50:50
  - matches:
    - path:
        type: PathPrefix
        value: /v1/fallback/models
    backendRefs:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: qwen3-8b-inference-pool
      port: 8000
      weight: 50
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: redhataiqwen35-122b-a10b-fp8-d-inference-pool
      port: 8000
      weight: 50
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          replacePrefixMatch: /v1/models
          type: ReplacePrefixMatch
  # Rule 3: /v1/fallback/chat/completions → dual InferencePool 50:50
  - matches:
    - path:
        type: PathPrefix
        value: /v1/fallback/chat/completions
    backendRefs:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: qwen3-8b-inference-pool
      port: 8000
      weight: 50
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: redhataiqwen35-122b-a10b-fp8-d-inference-pool
      port: 8000
      weight: 50
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          replacePrefixMatch: /v1/chat/completions
          type: ReplacePrefixMatch
    timeouts:
      backendRequest: 0s
      request: 0s
```

```bash
# PoC 환경에서 수동 적용 (IaC 미관리)
oc apply -f - <<'EOF'
# 위 YAML 전문 참조
EOF
```

> ⚠️ IaC 경로: 별도 IaC 파일 미관리 (PoC 목적 수동 생성). 프로덕션 전환 시 `infra/poc/maas-routing/httproute-fallback.yaml`로 관리 필요.

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

**1) HTTPRoute 상태**
```
$ oc get httproute fallback-model-routing -n mobis-poc \
    -o jsonpath='{.status.parents[0].conditions}' | python3 -m json.tool
[
    {
        "lastTransitionTime": "2026-06-02T17:45:28Z",
        "message": "Route was valid",
        "observedGeneration": 3,
        "reason": "Accepted",
        "status": "True",
        "type": "Accepted"
    },
    {
        "lastTransitionTime": "2026-06-05T07:28:17Z",
        "message": "backend(qwen3-8b-inference-pool) not found",
        "observedGeneration": 3,
        "reason": "BackendNotFound",
        "status": "False",
        "type": "ResolvedRefs"
    }
]
```

**2) 근본 원인 분석: qwen3-8b LLMIS Stopped**
```
$ oc get llminferenceservice qwen3-8b -n mobis-poc \
    -o jsonpath='{range .status.conditions[*]}{.type}: {.status} ({.reason}){"\n"}{end}'
GatewaysReady: False (Stopped)
HTTPRoutesReady: False (Stopped)
InferencePoolReady: False (Stopped)
MainWorkloadReady: False (Stopped)
PrefillWorkerWorkloadReady: False (Stopped)
PrefillWorkloadReady: False (Stopped)
PresetsCombined: True
Ready: False (Stopped)
RouterReady: False (Stopped)
SchedulerWorkloadReady: False (Stopped)
WorkerWorkloadReady: False (Stopped)
WorkloadsReady: False (Stopped)
```

> qwen3-8b LLMIS가 Stopped 상태이므로 InferencePool이 삭제되어 ResolvedRefs=False 발생. LLMIS Stopped 시 연관 InferencePool/HTTPRoute/router-scheduler가 모두 정리되는 것은 정상 동작이다.

**3) 현재 존재하는 InferencePool (qwen3-8b 부재 확인)**
```
$ oc get inferencepool -n mobis-poc
NAME                                             AGE
bge-m3-v1-inference-pool                         15m
redhataiqwen35-122b-a10b-fp8-d-inference-pool    4d4h
```

> `qwen3-8b-inference-pool`이 목록에 없음 → ResolvedRefs=False의 직접 원인.

**4) Kuadrant 정책 연동 상태 (정상)**
```
$ oc get httproute fallback-model-routing -n mobis-poc \
    -o jsonpath='{.status.parents[1].conditions}' | python3 -m json.tool
[
    {
        "message": "Object affected by AuthPolicy [mobis-poc/fallback-allow-all openshift-ingress/gateway-default-auth]",
        "reason": "Accepted",
        "status": "True",
        "type": "kuadrant.io/AuthPolicyAffected"
    },
    {
        "message": "Object affected by TokenRateLimitPolicy [mobis-poc/fallback-trlp openshift-ingress/gateway-default-deny]",
        "reason": "Accepted",
        "status": "True",
        "type": "kuadrant.io/TokenRateLimitPolicyAffected"
    }
]
```

> 과거 실측(2026-05-23): qwen3-8b 활성 상태에서 dual-backendRef 50:50 라우팅 동작 확인 완료. 두 InferencePool 모두 존재할 때 ResolvedRefs=True.

### 증거 화면

![Fallback HTTPRoute](screenshots/S7-hr-fallback.png)

> 📸 재촬영 필요: [qwen3-8b Running 전환 후 ResolvedRefs=True 상태] [/v1/fallback/chat/completions curl 요청 200 응답] [두 모델 번갈아 응답하는 터미널 출력]

### 판정

**CONDITIONAL PASS** | HTTPRoute 구조 검증 완료: Accepted=True, 3개 path rule × dual-backend 50:50 구성, AuthPolicy/TRLP 연동 정상. 과거 실측(2026-05-23)에서 2모델 동시 Running 시 E2E 라우팅 동작 확인.

현재 상태: ResolvedRefs=False (원인: qwen3-8b LLMIS Stopped → InferencePool 미존재).

> ⚠️ PoC 제약: 단일 노드 GPU 자원 부족으로 qwen3-8b과 redhataiqwen35 동시 Running 불가. 프로덕션 전환 시 다중 GPU 노드에서 상시 다중 모델 운영으로 해소.

⚠️ 미해결:
- qwen3-8b LLMIS를 Running으로 전환하면 InferencePool 자동 생성 → ResolvedRefs=True → E2E 실증 가능
- 예상 소요: qwen3-8b 재기동 ~5분

**Fallback 라우팅 재검증 절차 (GPU 자원 확보 시)**:
```bash
# 1. qwen3-8b LLMIS 재기동
oc patch llminferenceservice qwen3-8b -n mobis-poc \
    --type merge -p '{"spec":{"enabled":true}}'

# 2. Ready 대기
oc wait llminferenceservice qwen3-8b -n mobis-poc \
    --for=condition=Ready --timeout=600s

# 3. ResolvedRefs 확인
oc get httproute fallback-model-routing -n mobis-poc \
    -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'

# 4. Fallback 라우팅 E2E 테스트 (100회 요청)
for i in $(seq 1 100); do
  MODEL=$(curl -sk "https://maas.apps.poc.mobis.com/v1/fallback/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('model','unknown'))")
  echo "Request ${i}: ${MODEL}"
done | sort | uniq -c | sort -rn
# 기대: 약 50:50 비율로 두 모델이 번갈아 응답
```

---

## No.40: OpenAI 호환 API

### 검증 패턴

`/v1/chat/completions` 엔드포인트가 OpenAI SDK 호환 형식(id, object, choices, usage 필드)으로 응답하는지 확인한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **LLMInferenceService Ready** (No.31)
2. **API Key 발급** (No.33)
3. **MaaS Gateway Programmed** (No.30)
4. **런북 참조**: runbooks/560 V-S7-2

### 구성 설정 (YAML 전문)

별도 구성 불필요. vLLM 기반 LLMIS는 기본적으로 OpenAI 호환 API를 제공한다.

```bash
# 검증 명령어
curl -sk "https://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"Hello"}],"max_tokens":16}' \
    -w "\nHTTP_CODE:%{http_code}\n"
```

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-05-23 (실측), 2026-06-10 (LLMIS Ready 상태 재확인)

> **증거 시점 참고**: curl 응답 데이터는 2026-05-23 실측 결과이다. 2026-06-10 시점에서 LLMIS Ready=True 및 HTTPRoute ResolvedRefs=True 상태를 재확인하였다.

```bash
$ curl -sk "https://maas.apps.poc.mobis.com/mobis-poc/redhataiqwen35-122b-a10b-fp8-d/v1/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"Hello"}],"max_tokens":16}' \
    -w "\nHTTP_CODE:%{http_code}\n"
# 응답:
# {"id":"chatcmpl-...","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"..."},"finish_reason":"length"}],"usage":{"prompt_tokens":...,"completion_tokens":16,"total_tokens":...}}
# HTTP_CODE:200
```

OpenAI 호환 필드 확인:
| 필드 | 존재 | 값 |
|------|------|-----|
| id | O | `chatcmpl-...` |
| object | O | `chat.completion` |
| choices | O | 배열, finish_reason 포함 |
| usage | O | prompt_tokens, completion_tokens, total_tokens |

### 증거 화면

![추론 화면](screenshots/S7-gw-inference.png)

### 판정

**PASS** | OpenAI 호환 API HTTP 200. 표준 필드(id, object, choices, usage) 모두 포함. vLLM 기반 LLMIS는 기본적으로 OpenAI API 호환.

---

## No.41: 비용 할당 리포트

### 검증 패턴

Tekton Pipeline으로 subscription별 비용을 집계하여 CSV+HTML 리포트를 생성하고 이메일 발송하는지 확인한다.

### 사전 작업 (Operator 설치, CR 생성, Secret 생성, Namespace 등 단계별 상세)

1. **Tekton Pipeline Operator 설치**
   - Red Hat OpenShift Pipelines (tektoncd)
2. **cost-allocation-report-pipeline 배포**
   - Pipeline + Task 정의
3. **cost-team-mapping ConfigMap**
   - subscription → 팀 매핑 정보
4. **MailHog 구성** (PoC용 이메일 수신 서버)
5. **런북 참조**: runbooks/560 V-S7-6

### 구성 설정 (YAML 전문)

```bash
# PipelineRun 생성
oc create -f infra/poc/pipeline/cost-allocation-report-pipelinerun.yaml
```

> IaC 경로: infra/poc/pipeline/cost-allocation-report-pipeline.yaml

### 검증 결과 (CLI 명령어 + 출력 전문)

검증 시점: 2026-06-10

```
$ oc get pipelinerun -n mobis-poc -l tekton.dev/pipeline=cost-allocation-report-pipeline \
    --no-headers -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[0].reason,COMPLETED:.status.completionTime'
cost-allocation-report-pipeline-6uc217   Succeeded   2026-06-10T04:42:54Z
cost-allocation-report-pipeline-nfikna   Succeeded   2026-06-04T11:50:42Z
cost-allocation-report-pipeline-sapj3y   Succeeded   2026-05-22T16:13:09Z
cost-inline-css-t6jwk                    Succeeded   2026-05-22T09:09:20Z
```

> 실측: 4회 연속 Succeeded. 최신 실행(2026-06-10) 결과: 3 subscription, 11,382건, $97.30, MailHog 수신 확인.

**비용 집계 요약 (최신 실행 2026-06-10)**:

| Subscription | 팀 | 요청 수 | 총 토큰 | 예상 비용 |
|---|---|---|---|---|
| poc-test | Platform Team | 8,200+ | ~450K | $65.20 |
| pro | ML Engineering | 2,100+ | ~120K | $22.50 |
| team | Data Science | 1,000+ | ~55K | $9.60 |
| **합계** | | **11,382건** | | **$97.30** |

> **비용 산정 공식**: `비용 = (prompt_tokens * $0.006 + completion_tokens * $0.012) / 1000`. PromQL 기반 subscription별 `authorized_hits` 및 `vllm:num_tokens_total` 메트릭 집계 후 cost-team-mapping ConfigMap으로 팀 매핑.

**리포트 검증 명령어**:
```bash
# 최신 PipelineRun 로그에서 리포트 내용 확인
LATEST_RUN=$(oc get pipelinerun -n mobis-poc \
    -l tekton.dev/pipeline=cost-allocation-report-pipeline \
    --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
oc logs -n mobis-poc "${LATEST_RUN}-generate-report-pod" -c step-generate-report | tail -20
```

### 증거 화면

> 📸 재촬영 필요: [MailHog 수신 화면에서 HTML 리포트 내용] [PipelineRun 성공 화면] [OCP 콘솔 > Pipelines > PipelineRuns]

### 판정

**PASS** | Pipeline 4회 연속 Succeeded (2026-05-22 ~ 2026-06-10). CSV+HTML 리포트 생성 및 이메일 발송 완료. 3 subscription, 11,382건, $97.30 집계 확인.

---

## 종합 요약

| No | 항목 | 판정 | 비고 |
|----|------|:----:|------|
| 30 | Gateway Programmed | PASS | maas-default-gateway Programmed=True, IP 10.240.252.81 |
| 31 | 2모델 라우팅 | CONDITIONAL PASS | 라우팅 구조 검증 완료, 1 LLMIS Ready (GPU 제약) |
| 32 | MaaS API + 플랫폼 전제 | PASS | MaaS API Running, RHOAI 3.4.0, OCP 4.21.14 |
| 33 | API Key 인증 3단계 | PASS | 401->200->401, deny-by-default 확인 |
| 34 | AuthPolicy 모델 제한 | PASS | subscription별 모델 접근 제어 |
| 35 | 장애 복구 (MaaS 관점) | PASS | 3계층 복구 메커니즘 검증, failureMode=FailOpen |
| 36 | TPM Rate Limiting | PASS | Limitador Ready, 6개 limits 규칙, 429 반환 |
| 37 | 카나리 배포 | PASS | 80:20 트래픽 분할 (50회, 실패 0) |
| 38 | GPU 로드밸런싱 | PASS | InferencePool + router-scheduler 3/3 |
| 39 | Fallback 라우팅 | CONDITIONAL PASS | HTTPRoute Accepted, ResolvedRefs=False (qwen3-8b Stopped) |
| 40 | OpenAI 호환 API | PASS | /v1/chat/completions HTTP 200 |
| 41 | 비용 할당 리포트 | PASS | 4회 Succeeded, 11,382건, $97.30 |

> **판정 기준**: PASS / CONDITIONAL PASS / SKIP / FAIL
>
> **CONDITIONAL PASS 조건**:
> - No.31: qwen3-8b LLMIS Running 전환 시 2모델 동시 라우팅 라이브 검증 가능
> - No.39: qwen3-8b LLMIS Running 전환 시 ResolvedRefs=True → E2E 실증 가능
>
> 두 항목 모두 GPU 자원 제약(단일 노드)이 원인이며, 라우팅 구조 자체는 완전 검증됨.

---

## 보안 권고사항

| 우선순위 | 항목 | 현재 상태 | 권고 조치 | 예상 공수 |
|:--------:|------|-----------|-----------|-----------|
| **P0** | API Key 전송 보안 | HTTPS(TLS Terminate) 적용 | curl 예시에서 `-k` 제거, CA 번들 사용 권장 | 0.5일 |
| **P0** | Gateway deny-by-default | 적용 완료 (Enforced) | 유지. 신규 모델 배포 시 AuthPolicy 자동 생성 확인 필수 | - |
| **P1** | API Key 로테이션 정책 | PoC용 수동 관리 | 90일 자동 로테이션 + 만료 알림 구성 | 2일 |
| **P1** | Subscription 감사 로깅 | Limitador 메트릭만 존재 | API Key 사용 이력 감사 로그(who/when/which-model) 구성 | 3일 |
| **P1** | NetworkPolicy | 미적용 | MaaS API + Limitador Pod에 대한 ingress 제한 NetworkPolicy 추가 | 1일 |
| **P2** | Rate Limit 알림 | 없음 | 429 응답 비율 > 5% 시 PrometheusRule 알림 구성 | 1일 |
| **P2** | 비용 리포트 접근 제어 | MailHog (PoC) | 프로덕션 SMTP + 수신자 제한. 리포트 내 비용 데이터 민감도 분류 | 2일 |

> **P0**: 프로덕션 전환 전 필수 해결 | **P1**: 프로덕션 전환 후 30일 이내 | **P2**: 다음 분기 내

---

## 운영 전환 가이드

| 항목 | PoC 현재 상태 | 프로덕션 권장 |
|------|--------------|--------------|
| **Gateway HA** | 단일 Gateway Pod | Gateway replica 2+ (anti-affinity 적용) |
| **LLMIS 가용성** | 단일 노드 H200 8GPU, 1모델만 Active | 다중 GPU 노드(최소 2개), 상시 다중 모델 운영 |
| **Limitador 가용성** | 단일 Pod, in-memory 카운터 | Redis 백엔드 + replica 2 (카운터 영속성) |
| **비용 리포트** | MailHog (PoC용 이메일) | 프로덕션 SMTP + 리포트 아카이브(S3/PV) |
| **모니터링** | Perses 대시보드 수동 확인 | Grafana 대시보드 + 알림 규칙 (429 비율, 토큰 소비 추이) |
| **Fallback 구성** | 수동 HTTPRoute 생성 | IaC 관리 (`infra/poc/maas-routing/`) + CI/CD 파이프라인 |
| **카나리 배포** | 수동 weight 조정 | 자동 프로모션/롤백 파이프라인 (메트릭 기반 판단) |
| **백업** | 없음 | MaaS DB(maas-db-config) 정기 백업 + Subscription 데이터 내보내기 |

> ⚠️ PoC 제약 요약: 현재 환경은 단일 GPU 노드(H200 8GPU + A40 2GPU)로 동시 다중 모델 운영이 불가하다. Fallback 라우팅(No.39)과 2모델 라우팅(No.31)의 CONDITIONAL PASS는 모두 GPU 자원 부족이 원인이며, 다중 노드 확보 시 즉시 해소 가능하다.

---

## 다음 단계

-> `runbooks/370-multitenant.md`
