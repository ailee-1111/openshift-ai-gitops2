# 303 — EvalHub 설치 및 검증

## 어떤 경우 필요한가

LLM 모델 평가(벤치마크)를 RHOAI Dashboard에서 관리하려면 EvalHub를 배포해야 한다. EvalHub는 lm-evaluation-harness, RAGAS, Garak, GuideLLM, LightEval 등 여러 평가 프레임워크를 단일 REST API로 오케스트레이션하며, MLflow와 연동하여 실험 결과를 추적한다.

**참조:**
- [eval-hub/eval-hub](https://github.com/eval-hub/eval-hub) — EvalHub 소스 (Go, Apache 2.0, v0.3.0)
- [trustyai-service-operator](https://github.com/trustyai-explainability/trustyai-service-operator) — TrustyAI Operator v1.38.0 (5개 CRD 관리)
- [lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness) — EleutherAI 평가 프레임워크 (v0.4.12, 60+ 벤치마크)
- RHOAI 3.4 TrustyAI 문서

## TrustyAI Operator CRD 체계

TrustyAI Service Operator(v1.38.0)가 관리하는 5개 CRD:

| CRD | API Group | 용도 |
|-----|-----------|------|
| **TrustyAIService** | `tas/v1` | 모델 설명성, 공정성 모니터링, 드리프트 추적 |
| **LMEvalJob** | `lmes/v1alpha1` | LLM 평가 작업 실행 (lm-evaluation-harness 래핑) |
| **EvalHub** | `evalhub/v1alpha1` | 멀티 프레임워크 평가 오케스트레이션 + Dashboard 백엔드 |
| **GuardrailsOrchestrator** | `gorch/v1alpha1` | LLM 가드레일 (PII/HAP/프롬프트인젝션 감지) |
| **NemoGuardrails** | `nemo_guardrails/v1alpha1` | NVIDIA NeMo 가드레일 |

### EvalHub CR 동작 원리

- DB 필수 (SQLite 또는 PostgreSQL) — API 키 메타데이터, 평가 결과 저장
- Provider/Collection ConfigMap을 오퍼레이터 NS에서 인스턴스 NS로 자동 복사
- 테넌트 NS에 Job SA + RoleBinding 자동 생성 (멀티테넌트 지원)
- Prometheus 메트릭(`/api/v1/metrics`), OpenShift Route 지원

### LMEvalJob 라이프사이클

```
New → Scheduled → Running → Complete
```

- Pod 구성: main(lm-eval) + driver sidecar(상태 보고) + user sidecars(optional)
- `local-completions` 모드: vLLM InferenceService의 OpenAI 호환 API를 대상으로 평가
- 결과는 `status.results`에 저장, EvalHub + MLflow로 추적
- Kueue 통합 가능 (suspend/resume semantics)

## 전제 조건

- [ ] `runbooks/211-trustyai.md` 완료 — TrustyAIService Running
- [ ] `runbooks/212-mlflow.md` 완료 — MLflow Available
- [ ] `runbooks/300-model-serving.md` 완료 — InferenceService Ready
- [ ] DSC `trustyai.eval.lmeval.permitOnline: "allow"` 설정 완료 (211에서 수행)
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`, `TOKENIZER_MODEL`

## 아키텍처

```
┌─ RHOAI Dashboard ──────────────────────┐
│  Evaluations 탭 ──→ EvalHub API (8443) │
└────────────────────┬───────────────────┘
                     │
┌────────────────────▼───────────────────┐
│  EvalHub (evalhub NS)                  │
│  - REST API (/api/v1)                  │
│  - Providers: lm-eval, garak, guidellm │
│  - Collections: leaderboard, safety    │
│  - Storage: SQLite (in-mem)            │
│  - MLflow 연동 (HTTPS, TLS skip)       │
└────────────────────┬───────────────────┘
                     │ Job 생성
┌────────────────────▼───────────────────┐
│  ${MODEL_NS} (mobis-poc)               │
│  - LMEvalJob Pod (평가 실행)            │
│  - vLLM InferenceService (대상 모델)    │
│  - TrustyAIService (메트릭)             │
└────────────────────────────────────────┘
```

## 실행

### 1. EvalHub CR 생성

> **주의**: RHOAI 3.4에서 EvalHub CR은 전용 `evalhub` NS 또는 `redhat-ods-applications` NS에 생성. Dashboard가 인식하려면 올바른 NS 필요.

~~~bash
set -a && source .env 2>/dev/null; set +a
: "${MODEL_NS:=mobis-poc}"

oc create namespace evalhub --dry-run=client -o yaml | oc apply -f -

oc apply -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: EvalHub
metadata:
  name: evalhub
  namespace: evalhub
spec:
  database:
    type: sqlite
    maxIdleConns: 5
    maxOpenConns: 25
  replicas: 1
  providers:
    - garak
    - garak-kfp
    - lm-evaluation-harness
    - guidellm
    - lighteval
  collections:
    - leaderboard-v2
    - safety-and-fairness-v1
    - toxicity-and-ethical-principles
  env:
    - name: MLFLOW_TRACKING_URI
      value: "https://mlflow.redhat-ods-applications.svc:8443"
    - name: MLFLOW_INSECURE_SKIP_VERIFY
      value: "true"
    - name: MLFLOW_WORKSPACE
      value: "${MODEL_NS}"
EOF

echo "EvalHub CR 대기 (최대 2분)..."
oc wait evalhub/evalhub -n evalhub \
  --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
  --timeout=120s 2>/dev/null || echo "WARNING: Ready 대기 타임아웃"
oc get evalhub -n evalhub
~~~

### 2. EvalHub RBAC — 대상 네임스페이스 권한 부여

> EvalHub이 evaluation job을 실행할 모든 네임스페이스에 아래 RBAC를 생성해야 한다.

~~~bash
# ServiceAccount
oc create sa evalhub-redhat-ods-applications-job -n "${MODEL_NS}" 2>/dev/null || true

# CA ConfigMap 복사 (evalhub NS → 대상 NS)
oc get configmap evalhub-service-ca -n evalhub -o json \
  | python3 -c "
import sys, json
cm = json.load(sys.stdin)
cm['metadata'] = {'name': 'evalhub-service-ca', 'namespace': '${MODEL_NS}'}
json.dump(cm, sys.stdout)
" | oc apply -f -

# MLflow 접근 권한
oc create rolebinding evalhub-mlflow-access-rb \
  --clusterrole=trustyai-service-operator-evalhub-mlflow-access \
  --serviceaccount=evalhub:evalhub-service \
  -n "${MODEL_NS}" 2>/dev/null || true

oc create rolebinding evalhub-mlflow-jobs-access-rb \
  --clusterrole=trustyai-service-operator-evalhub-mlflow-jobs-access \
  --serviceaccount=evalhub:evalhub-service \
  -n "${MODEL_NS}" 2>/dev/null || true

# Job 실행 권한
oc apply -n "${MODEL_NS}" -f - <<ROLE_EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: evalhub-job-access-role
  namespace: ${MODEL_NS}
rules:
- apiGroups: [""]
  resources: [configmaps, pods, pods/log, serviceaccounts, secrets, events]
  verbs: ["*"]
- apiGroups: [batch]
  resources: [jobs]
  verbs: ["*"]
- apiGroups: [trustyai.opendatahub.io]
  resources: [status-events]
  verbs: [create]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: evalhub-job-access-rb
  namespace: ${MODEL_NS}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: evalhub-job-access-role
subjects:
- kind: ServiceAccount
  name: evalhub-service
  namespace: evalhub
ROLE_EOF

echo "RBAC 설정 완료"
~~~

### 3. LMEvalJob 실행 (모델 평가)

> LMEvalJob은 [lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness) v0.4.12를 Kubernetes Job으로 래핑한다. `local-completions` 모드로 vLLM의 OpenAI 호환 API를 대상으로 평가한다.

~~~bash
oc apply -n "${MODEL_NS}" -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: ${MODEL_NAME}-eval
spec:
  model: local-completions
  allowOnline: true
  modelArgs:
    - name: model
      value: ${MODEL_NAME}
    - name: base_url
      value: "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/completions"
    - name: tokenizer_backend
      value: huggingface
    - name: tokenized_requests
      value: "false"
    - name: tokenizer
      value: "${TOKENIZER_MODEL:-HuggingFaceTB/SmolLM2-135M}"
  taskList:
    taskNames:
      - "hellaswag"
  limit: "3"
  batchSize: "1"
EOF

echo "LMEvalJob 대기 (최대 5분)..."
for i in $(seq 1 10); do
  STATE=$(oc get lmevaljob "${MODEL_NAME}-eval" -n "${MODEL_NS}" \
    -o jsonpath='{.status.state}' 2>/dev/null)
  echo "  ${i}0초: state=${STATE}"
  [ "${STATE}" = "Complete" ] && break
  sleep 30
done
~~~

#### 사용 가능한 평가 태스크 (lm-evaluation-harness)

| 태스크 | 유형 | 설명 | 용도 |
|--------|------|------|------|
| `hellaswag` | 상식 추론 | 문장 완성 | 기본 검증 (현재 사용 중) |
| `mmlu` | 지식 | 57개 과목 객관식 | 종합 지식 평가 |
| `gsm8k` | 수학 | 초등 수학 문제 | 수리 추론 |
| `arc_challenge` | 과학 | 어려운 과학 질문 | 과학 추론 |
| `winogrande` | 상식 | 대명사 해석 | 언어 이해 |
| `truthfulqa` | 진실성 | 거짓 정보 생성 탐지 | 안전성 평가 |
| `lambada_openai` | 언어 모델링 | 마지막 단어 예측 | 기본 언어 능력 |
| `leaderboard` | 종합 | Open LLM Leaderboard 태스크 그룹 | 모델 랭킹 |

> 전체 목록: `lm_eval ls tasks` (60+ 벤치마크, 수백 하위 태스크)

#### 멀티 태스크 평가 예시

~~~bash
oc apply -n "${MODEL_NS}" -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: ${MODEL_NAME}-eval-multi
spec:
  model: local-completions
  allowOnline: true
  modelArgs:
    - name: model
      value: ${MODEL_NAME}
    - name: base_url
      value: "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/completions"
    - name: tokenizer_backend
      value: huggingface
    - name: tokenized_requests
      value: "false"
    - name: tokenizer
      value: "${TOKENIZER_MODEL:-HuggingFaceTB/SmolLM2-135M}"
  taskList:
    taskNames:
      - "hellaswag"
      - "arc_easy"
      - "lambada_openai"
  limit: "5"
  batchSize: "1"
EOF
~~~

#### CLI 직접 평가 (vLLM 대상)

클러스터 외부 또는 디버깅용으로 lm-evaluation-harness를 직접 실행:

~~~bash
pip install "lm_eval[api]"

lm_eval --model local-completions \
  --model_args model=${MODEL_NAME},base_url=http://${MODEL_NAME}-metrics.${MODEL_NS}.svc:8080/v1/completions,tokenized_requests=False \
  --tasks hellaswag \
  --limit 3
~~~

### 4. Dashboard Pod 재시작 (MLflow 인식)

> MLflow CR 생성 후 Dashboard Pod를 재시작해야 `mlflow-ui` 컨테이너가 MLflow를 인식한다.

~~~bash
oc rollout restart deploy/rhods-dashboard -n redhat-ods-applications
oc rollout status deploy/rhods-dashboard -n redhat-ods-applications --timeout=120s
~~~

---

## 검증 완료

### V-1: EvalHub CR Ready

~~~bash
oc get evalhub evalhub -n evalhub -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'
echo ""
# 기대: Ready=True
# PASS: [   ]  FAIL: [   ]
~~~

### V-2: EvalHub Pod Running

~~~bash
oc get pods -n evalhub -l app=eval-hub --no-headers
# 기대: 1/1 Running
# PASS: [   ]  FAIL: [   ]
~~~

### V-3: EvalHub Health

~~~bash
oc exec -n evalhub deploy/evalhub -- curl -sk https://localhost:8443/api/v1/health
# 기대: {"status":"healthy","build":"0.3.0"}
# PASS: [   ]  FAIL: [   ]
~~~

### V-4: Providers 활성화

~~~bash
oc get evalhub evalhub -n evalhub -o jsonpath='{.status.activeProviders}'
# 기대: ["garak","garak-kfp","lm-evaluation-harness","guidellm","lighteval"]
# PASS: [   ]  FAIL: [   ]
~~~

### V-5: LMEvalJob Complete

~~~bash
oc get lmevaljob ${MODEL_NAME}-eval -n ${MODEL_NS} -o jsonpath='state={.status.state}'
# 기대: state=Complete
# PASS: [   ]  FAIL: [   ]
~~~

### V-6: Dashboard Evaluations 탭

RHOAI Dashboard → Evaluations 탭 접근
- 기대: EvalHub 연결 정상, providers 목록 표시
- PASS: [   ]  FAIL: [   ]

### 검증 요약

| # | 항목 | 기준 | 판정 |
|---|------|------|:----:|
| V-1 | EvalHub CR | Ready=True | |
| V-2 | Pod | 1/1 Running | |
| V-3 | Health | healthy | |
| V-4 | Providers | 5개 활성 | |
| V-5 | LMEvalJob | Complete | |
| V-6 | Dashboard | Evaluations 탭 정상 | |

---

## 식별 방법 (이슈 진단)

### EvalHub가 Dashboard에서 안 보이는 경우

~~~bash
# 1. EvalHub CR 존재 확인
oc get evalhub -A

# 2. CR이 올바른 NS에 있는지 확인 (evalhub 또는 redhat-ods-applications)
oc get evalhub -n evalhub -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'

# 3. Pod Running 확인
oc get pods -A -l app=eval-hub

# 4. Service 존재 확인
oc get svc -n evalhub --no-headers | grep eval
~~~

### EvalHub API 401 Unauthorized

~~~bash
# EvalHub는 SA 토큰 기반 인증. Dashboard에서 호출 시 자동 처리.
# CLI에서 직접 호출 시:
TOKEN=$(oc create token evalhub-service -n evalhub --duration=600s)
oc exec -n evalhub deploy/evalhub -- curl -sk \
  -H "Authorization: Bearer ${TOKEN}" \
  https://localhost:8443/api/v1/evaluations/providers
~~~

---

## 실패 시

- **EvalHub Pod Pending** → PVC 또는 리소스 부족. `oc describe pod -n evalhub -l app=eval-hub`
- **"Evaluations unavailable"** → EvalHub CR이 올바른 NS에 있는지 확인. Dashboard 연결 설정 확인
- **"MLflow is not configured"** → Dashboard Pod 재시작 필요 (Step 4)
- **"Error loading experiments"** → `mlflow-ui` 컨테이너 로그: `oc logs <dashboard-pod> -n redhat-ods-applications -c mlflow-ui --tail=10`
- **eval job Pod FailedCreate "SA not found"** → 대상 NS에 `evalhub-redhat-ods-applications-job` SA 생성 (Step 2)
- **eval job Pod FailedMount "configmap not found"** → 대상 NS에 `evalhub-service-ca` ConfigMap 복사 (Step 2)
- **GuideLLM 벤치마크 멈춤** → 자가서명 TLS 환경에서 HTTPS Route 접근 시 TLS 검증 실패. 내부 svc URL 사용 (Product Gap)
- **MLflow 403** → `MLFLOW_WORKSPACE`가 대상 NS와 일치하는지 확인. RoleBinding 존재 여부 확인

## 알려진 제약 (RHOAI 3.4 Tech Preview)

| # | 제약 | 우회 방법 |
|---|------|----------|
| 1 | GuideLLM — 자가서명 TLS 환경에서 HTTPS Route 접근 불가 | 내부 svc URL(http) 사용 |
| 2 | RBAC 자동 프로비저닝 미지원 — 대상 NS에 SA/ConfigMap/RoleBinding 수동 생성 필요 | Step 2로 수동 설정 |
| 3 | MLflow 동적 감지 불가 — MLflow CR 생성 후 Dashboard Pod 수동 재시작 필요 | Step 4 |
| 4 | LMEvalJob `local-completions` 모드만 내부 svc URL(http) 정상 동작 | HTTPS Route 대신 ClusterIP svc 사용 |
| 5 | EvalHub API 인증 — SA 토큰 기반, Dashboard 외부 CLI 접근 시 수동 토큰 발급 필요 | `oc create token` 사용 |

## Mobis 클러스터 실측 (2026-05-19)

| 항목 | 값 |
|------|-----|
| EvalHub CR | `evalhub` NS, Ready=True |
| EvalHub 버전 | 0.3.0 |
| Pod | 1/1 Running |
| Providers | garak, garak-kfp, lm-evaluation-harness, guidellm, lighteval |
| Collections | leaderboard-v2, safety-and-fairness-v1, toxicity-and-ethical-principles |
| LMEvalJob | smollm2-135m-eval-v3 Complete (hellaswag) |
| Service | evalhub:8443 (ClusterIP, HTTPS) |
| RBAC | mobis-poc NS에 SA/RoleBinding 구성 완료 |

## 다음 단계

→ `runbooks/500-model-serving-validation.md` — S1 모델 서빙 검증
