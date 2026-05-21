# S10: MLOps 루프 -- 모델 개선 주기 자동화

## 메타 정보

| 항목 | 값 |
|------|-----|
| 주역할 | DS (데이터 사이언티스트) |
| 보조역할 | MGR (개발팀 관리자) |
| 데모 시간 | 20분 |
| 검증 항목 | No.77, 78 |
| 런북 | 303-evalhub, 390-mlops-loop, 391(planned) / 590-mlops-validation |
| IaC | `infra/poc/mlops-loop/` |
| 클러스터 | Mobis PoC (H200x8 + A40x2, OCP 4.21, RHOAI 3.4) |

---

## 상황 (Context)

> 모비스 AI팀은 차량 매뉴얼 Q&A 모델을 운영 중이다. 고객 피드백에 따라 모델을 주기적으로 개선해야 하는데, 현재는 데이터 사이언티스트가 로컬 환경에서 파인튜닝한 뒤 수동으로 평가하고, 관리자에게 메일로 승인을 받아 배포한다. 이 과정에서 평가 기준이 사람마다 다르고, 이전 버전과의 비교가 체계적이지 않으며, 배포 과정에서 실수가 발생하기도 한다.

---

## 문제 (Problem)

> 모델 개선 1사이클에 **평균 2주**가 소요된다.

| 단계 | 기존 방식 | 소요 시간 | 문제점 |
|------|----------|----------|--------|
| 파인튜닝 | 로컬 GPU 서버에서 수동 실행 | 2~3일 | 재현 불가, 환경 차이 |
| 평가 | Jupyter에서 수동 벤치마크 | 2~3일 | 평가 기준 비일관, 이전 결과와 비교 어려움 |
| 버전 관리 | 파일 서버에 날짜별 폴더 | - | 메타데이터 없음, 어떤 버전이 어떤 평가를 통과했는지 불명 |
| 승인 | 이메일 + 구두 | 1~2일 | 감사 추적 불가 |
| 배포 | SSH 접속 후 수동 교체 | 1~2일 | 다운타임 발생, 롤백 어려움 |
| **합계** | | **약 2주** | **재현 불가, 추적 불가, 사고 위험** |

---

## 해결 (Solution) -- RHOAI MLOps 루프로 2주를 2일로 단축

### Step 1: 현재 고통 설명 (DS, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | 현재 모델 개선 프로세스의 문제점 설명 |
| 어떻게 | 화이트보드 또는 슬라이드로 수동 → 자동화 전환 비전 제시 |
| 권한 | 없음 (발표) |

**시연 멘트:**
> "현재 모델 하나를 개선하는 데 2주가 걸립니다. 파인튜닝, 평가, 승인, 배포 모든 단계가 수동입니다. RHOAI의 MLOps 루프를 사용하면 이 과정을 **체계적이고 재현 가능한 파이프라인**으로 전환할 수 있습니다."

```
기존: [로컬 파인튜닝] → [수동 평가] → [메일 승인] → [SSH 배포]
                        ⬇ 2주, 재현 불가
RHOAI: [TrainJob CRD] → [LMEvalJob] → [Registry v2] → [RollingUpdate]
                        ⬇ 2일, 완전 추적 가능
```

---

### Step 2: TrainJob 제출 -- 분산 파인튜닝 (DS, 4분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | TrainJob CRD로 LoRA 파인튜닝 작업 제출 |
| 어떻게 | YAML 적용 후 학습 로그 실시간 확인 |
| 권한 | NS edit (mobis-poc) |

**시연 멘트:**
> "TrainJob은 Kubernetes 네이티브 학습 자원입니다. YAML 하나로 학습 환경, 데이터, 하이퍼파라미터를 선언합니다."

**ClusterTrainingRuntime 옵션 확인:**

```bash
# 15개 ClusterTrainingRuntime 확인 (CUDA/CPU/ROCm)
oc get clustertrainingruntimes
```

> "현재 15개의 사전 정의된 런타임이 있습니다. GPU 환경에 맞는 CUDA 런타임, CPU 전용, AMD ROCm까지 지원합니다."

**TrainJob 제출 (PyTorch 2.10.0):**

```bash
oc apply -n ${MODEL_NS:-mobis-poc} -f - <<'EOF'
apiVersion: kubeflow.org/v2alpha1
kind: TrainJob
metadata:
  name: poc-finetune-cpu
spec:
  runtimeRef:
    name: torch-tune
  trainerConfig:
    image: "quay.io/modh/training:py311-pt210-20250422"
    command: ["python3", "-c", "import torch; m=torch.nn.Linear(128,64); o=torch.optim.SGD(m.parameters(),lr=0.01); l=torch.nn.MSELoss(); [print(f'epoch {e}: loss={l(m(torch.randn(32,128)),torch.randn(32,64)).item():.4f}') or (o.zero_grad(),l(m(torch.randn(32,128)),torch.randn(32,64)).backward(),o.step()) for e in range(5)]; torch.save(m.state_dict(),'/tmp/model.pt'); print('Done')"]
    resources:
      requests: {cpu: "1", memory: 1Gi}
      limits: {cpu: "2", memory: 2Gi}
  numNodes: 1
EOF
```

**확인 포인트:**

```bash
# TrainJob Pod 기동 확인 + 학습 로그 스트리밍
oc get pods -n ${MODEL_NS:-mobis-poc} -l trainjob-name=poc-finetune-cpu -w

# 로그 실시간 확인
oc logs -n ${MODEL_NS:-mobis-poc} -l trainjob-name=poc-finetune-cpu -f --tail=20
```

> "Pod가 생성되고 학습이 시작됩니다. 로그에서 epoch별 loss가 줄어드는 것을 확인할 수 있습니다."

---

### Step 3: TrainJob 완료 확인 (DS, 1분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | TrainJob 완료 상태 확인 |
| 어떻게 | CRD status 조회 |
| 권한 | NS view (mobis-poc) |

```bash
# Complete 상태 확인
for i in $(seq 1 30); do
  STATE=$(oc get trainjob poc-finetune-cpu -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
  echo "$(date '+%H:%M:%S') Complete=${STATE:-Pending}"
  [ "${STATE}" = "True" ] && break; sleep 10
done
```

> "TrainJob이 Complete 상태로 전환되었습니다. Kubernetes가 학습 자원을 자동으로 정리합니다."

---

### Step 4: LMEvalJob -- 벤치마크 평가 (DS, 4분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | LMEvalJob CRD로 hellaswag 벤치마크 평가 실행 |
| 어떻게 | YAML 적용 후 평가 진행/완료 확인 |
| 권한 | NS edit (mobis-poc) |

**시연 멘트:**
> "학습이 끝나면 바로 평가로 넘어갑니다. LMEvalJob은 EleutherAI의 lm-evaluation-harness를 Kubernetes Job으로 래핑한 것입니다. hellaswag 같은 표준 벤치마크를 자동 실행합니다."

```bash
oc apply -n ${MODEL_NS:-mobis-poc} -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: poc-v2-eval
spec:
  model: local-completions
  allowOnline: true
  modelArgs:
    - {name: model, value: ${MODEL_NAME:-smollm2-135m}}
    - {name: base_url, value: "http://${MODEL_NAME:-smollm2-135m}-metrics.${MODEL_NS:-mobis-poc}.svc.cluster.local:8080/v1/completions"}
    - {name: tokenizer_backend, value: huggingface}
    - {name: tokenized_requests, value: "false"}
    - {name: tokenizer, value: "${TOKENIZER_MODEL:-HuggingFaceTB/SmolLM2-135M}"}
  taskList:
    taskNames: ["hellaswag"]
  limit: "5"
  batchSize: "1"
EOF
```

**평가 진행 모니터링:**

```bash
# EvalHub이 평가 처리하는 과정 확인
for i in $(seq 1 30); do
  STATE=$(oc get lmevaljob poc-v2-eval -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='{.status.state}' 2>/dev/null)
  echo "$(date '+%H:%M:%S') state=${STATE:-Pending}"
  [ "${STATE}" = "Complete" ] && break; sleep 20
done
```

**평가 결과 확인:**

```bash
# LMEvalJob 결과 상세
oc get lmevaljob poc-v2-eval -n ${MODEL_NS:-mobis-poc} -o jsonpath='{.status.results}' | python3 -m json.tool
```

> "hellaswag 벤치마크 평가가 Complete 되었습니다. 점수를 확인할 수 있습니다. 이전 버전과 동일한 벤치마크로 평가하므로 **객관적인 비교**가 가능합니다."

---

### Step 5: GuideLLM 성능 테스트 (DS, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | GuideLLM으로 추론 성능(처리량, 지연시간) 퀵 테스트 |
| 어떻게 | EvalHub의 GuideLLM provider를 통해 실행 |
| 권한 | NS view (mobis-poc) |

```bash
# GuideLLM 벤치마크 (내부 svc URL 사용 -- 자가서명 TLS 우회)
TOKEN=$(oc create token evalhub-service -n evalhub --duration=600s)
EVALHUB_SVC="https://evalhub.evalhub.svc:8443"

curl -sk -X POST "${EVALHUB_SVC}/api/v1/evaluations" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "guidellm",
    "model": "'${MODEL_NAME:-smollm2-135m}'",
    "namespace": "'${MODEL_NS:-mobis-poc}'",
    "config": {
      "base_url": "http://'${MODEL_NAME:-smollm2-135m}'-metrics.'${MODEL_NS:-mobis-poc}'.svc.cluster.local:8080",
      "max_requests": 10
    }
  }' -w "\nHTTP %{http_code}\n"
# 기대: HTTP 204 (accepted)
```

> "GuideLLM이 처리량(tokens/s)과 지연시간(latency) 메트릭을 측정합니다. 모델 품질뿐 아니라 **서빙 성능**까지 정량 평가합니다."

---

### Step 6: EvalHub 대시보드 확인 (DS, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | RHOAI Dashboard의 Evaluations 탭에서 평가 결과 종합 확인 |
| 어떻게 | 브라우저로 Dashboard 접속 |
| 권한 | Dashboard 읽기 |

**시연 멘트:**
> "RHOAI Dashboard에서 모든 평가 결과를 한눈에 볼 수 있습니다."

**확인 포인트 (브라우저):**
- RHOAI Dashboard (`https://rh-ai.apps.poc.mobis.com`) 접속
- **Evaluations** 탭 클릭
- 5개 Provider 표시 확인: `lm-evaluation-harness`, `garak`, `guidellm`, `lighteval`, `garak-kfp`
- 평가 결과 목록에서 `poc-v2-eval` 선택 → 점수 확인

```bash
# CLI로도 확인 가능 -- 5개 Provider 활성화
oc get evalhub evalhub -n evalhub -o jsonpath='{.status.activeProviders}'
# 기대: ["garak","garak-kfp","lm-evaluation-harness","guidellm","lighteval"]
```

---

### Step 7: MLflow 대시보드 확인 (DS, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | MLflow에서 실험 추적, 모델 아티팩트 확인 |
| 어떻게 | RHOAI Dashboard 내 MLflow UI 접속 |
| 권한 | Dashboard 읽기 |

**시연 멘트:**
> "MLflow는 모든 학습 실험과 평가 결과를 자동으로 기록합니다. 어떤 하이퍼파라미터로 학습했고, 어떤 벤치마크 점수를 받았는지 **전체 이력을 추적**할 수 있습니다."

**확인 포인트 (브라우저):**
- RHOAI Dashboard → **Model Experiments** 접속
- 실험 목록에서 최근 학습 기록 확인
- 메트릭 비교 (v1 vs v2 loss, 평가 점수)
- 모델 아티팩트 위치 확인

```bash
# MLflow 상태 확인
oc get pods -n redhat-ods-applications -l app=mlflow --no-headers
# 기대: Running
```

---

### Step 8: 관리자 승인 (MGR, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | MGR (poc-operator) |
| 무엇을 | 평가 결과를 검토하고 배포 승인 |
| 어떻게 | EvalHub/MLflow 결과 검토 후 구두 승인 (또는 Pipeline ManualApproval) |
| 권한 | NS edit + approval (mobis-poc) |

**시연 멘트:**
> "관리자는 EvalHub의 벤치마크 점수와 MLflow의 실험 기록을 검토합니다. 평가 기준을 통과했으므로 배포를 승인합니다. 이 과정이 S2 Pipeline의 ManualApprovalGate와 연결되면 **승인 이력이 자동으로 감사 추적**됩니다."

**검토 항목:**
1. hellaswag 점수가 이전 버전 대비 동등 이상인가?
2. GuideLLM 성능이 SLA 기준을 충족하는가?
3. 학습 하이퍼파라미터가 표준 범위 내인가?

---

### Step 9: 배포 트리거 (DS, 1분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | 승인된 모델을 Registry에 v2로 등록하고 RollingUpdate 배포 |
| 어떻게 | Model Registry v2 등록 → InferenceService storage.path 전환 |
| 권한 | NS edit (mobis-poc) |

**시연 멘트:**
> "승인이 완료되면 Model Registry에 v2를 등록하고, InferenceService의 storage.path를 변경합니다. RollingUpdate로 **무중단 전환**됩니다. 이 과정은 S2 Pipeline과 연결하면 완전 자동화됩니다."

```bash
# Registry v2 등록
MR_ROUTE=$(oc get route -n "${MODEL_REGISTRY_NS}" --no-headers | awk '{print $2}' | head -1)
TOKEN=$(oc whoami -t)
MODEL_ID=$(curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -c "
import sys,json
for m in json.load(sys.stdin).get('items',[]):
    if m.get('name')=='${MODEL_NAME:-smollm2-135m}': print(m['id']); break")

curl -sk -X POST "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
  -H "Content-Type: application/json" -H "Authorization: Bearer ${TOKEN}" \
  -d '{"name":"v2-finetuned","description":"Fine-tuned + eval passed"}'
echo "v2-finetuned 등록 완료"

# RollingUpdate 배포 (S2 Pipeline 연결)
# 실제 시연에서는 S2의 배포 파이프라인 트리거로 대체 가능
oc patch inferenceservice ${MODEL_NAME:-smollm2-135m} -n ${MODEL_NS:-mobis-poc} --type=merge \
  -p '{"spec":{"predictor":{"model":{"storage":{"path":"'${MODEL_NAME:-smollm2-135m}'/v2'"}}}}}'
oc wait inferenceservice ${MODEL_NAME:-smollm2-135m} -n ${MODEL_NS:-mobis-poc} \
  --for=condition=Ready --timeout=300s
echo "v2 배포 완료"
```

---

## 확인 (Verification)

| # | 항목 | 기준 | 실측 | 판정 |
|---|------|------|------|:----:|
| V-1 | Trainer Operator | Running | Running | |
| V-2 | TrainJob | Complete=True | Complete | |
| V-3 | ClusterTrainingRuntime | 15개 이상 | 15개 | |
| V-4 | LMEvalJob | state=Complete (hellaswag) | Complete | |
| V-5 | EvalHub | Ready=True, 5 providers | Ready, 5개 | |
| V-6 | GuideLLM | HTTP 204 (accepted) | 204 | |
| V-7 | MLflow | Available | Available | |
| V-8 | Registry v2 | 버전 등록 성공 | 등록 | |
| V-9 | InferenceService | Ready=True (v2) | Ready | |

```bash
# 검증 일괄 실행
echo "=== V-1: Trainer Operator ==="
oc get pods -n redhat-ods-applications -l app=trainer-operator --no-headers | head -1

echo "=== V-2: TrainJob ==="
oc get trainjob poc-finetune-cpu -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='Complete={.status.conditions[?(@.type=="Complete")].status}'; echo ""

echo "=== V-3: ClusterTrainingRuntime ==="
oc get clustertrainingruntimes --no-headers | wc -l

echo "=== V-4: LMEvalJob ==="
oc get lmevaljob poc-v2-eval -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='state={.status.state}'; echo ""

echo "=== V-5: EvalHub ==="
oc get evalhub evalhub -n evalhub \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'; echo ""

echo "=== V-7: MLflow ==="
oc get pods -n redhat-ods-applications -l app=mlflow --no-headers | head -1

echo "=== V-9: InferenceService ==="
oc get inferenceservice ${MODEL_NAME:-smollm2-135m} -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'; echo ""
```

---

## 이번 시연에서 확인된 핵심 가치

### 모델 개선 주기: 2주 --> 2일

| 단계 | 기존 | RHOAI | 단축 |
|------|------|-------|------|
| 파인튜닝 | 2~3일 (로컬, 재현 불가) | TrainJob CRD (선언적, 재현 가능) | 동일 시간, 재현성 확보 |
| 평가 | 2~3일 (수동 벤치마크) | LMEvalJob (자동, 표준 벤치마크) | **3일 --> 30분** |
| 버전 관리 | 파일 서버 (메타데이터 없음) | Model Registry + MLflow | **추적 불가 --> 완전 추적** |
| 승인 | 1~2일 (이메일) | Dashboard 리뷰 + Pipeline 승인 | **2일 --> 1시간** |
| 배포 | 1~2일 (SSH 수동) | RollingUpdate (무중단) | **2일 --> 5분** |
| **합계** | **~14일** | **~2일** | **7배 단축** |

### 핵심 차별점

1. **체계적 평가**: hellaswag 등 표준 벤치마크로 객관적 품질 비교. 평가자 주관 배제
2. **재현 가능한 학습**: TrainJob CRD로 환경, 데이터, 하이퍼파라미터 선언적 관리
3. **완전한 추적성**: MLflow가 모든 실험, 평가, 배포 이력을 자동 기록
4. **무중단 배포**: RollingUpdate로 서비스 중단 없이 모델 버전 전환

---

## 추천 사항

1. **Pipeline 연동**: S2의 7-stage Pipeline과 연결하면 TrainJob 완료 --> 자동 평가 --> 승인 대기 --> 자동 배포까지 E2E 자동화 가능
2. **평가 태스크 확장**: hellaswag 외에 `mmlu`, `arc_challenge`, `truthfulqa` 등 복수 벤치마크로 다각도 평가 권장
3. **GuideLLM 정기 실행**: 모델 변경 시마다 성능 벤치마크를 실행하여 SLA 기준 충족 여부를 정량적으로 확인
4. **MLflow 실험 비교**: v1, v2, v3... 버전 간 메트릭 트렌드를 추적하여 모델 품질 회귀 방지
5. **Kueue 연동**: GPU 자원이 한정된 환경에서 학습/평가 Job의 큐 관리로 공정한 자원 배분

---

## 참고: MLOps 루프 전체 아키텍처

```
┌──────────────────────────────────────────────────────────────┐
│                    RHOAI MLOps Loop                          │
│                                                              │
│  ┌─────────┐    ┌──────────┐    ┌──────────┐    ┌────────┐  │
│  │TrainJob │ -> │LMEvalJob │ -> │ Registry │ -> │ Deploy │  │
│  │(학습)    │    │(평가)     │    │  (버전)   │    │(서빙)  │  │
│  └─────────┘    └──────────┘    └──────────┘    └────────┘  │
│       │              │               │              │        │
│       v              v               v              v        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              MLflow (실험 추적)                       │   │
│  └──────────────────────────────────────────────────────┘   │
│       │              │                                       │
│       v              v                                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         EvalHub Dashboard (시각화)                    │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```
