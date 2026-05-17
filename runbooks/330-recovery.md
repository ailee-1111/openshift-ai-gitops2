# 330 — 장애복구 / 이중화 검증 (S4)

## 목적

서빙 중인 모델의 Pod 장애 시 자동 복구(ReplicaSet), RollingUpdate를 통한 무중단 교체, 노드 장애 시 페일오버가 정상 동작하는지 검증한다. 모델 버전 롤백 절차도 함께 확인한다.

## 전제 조건

- [ ] `runbooks/320-autoscaling.md` 완료 — ScaledObject Ready=True
- [ ] InferenceService Ready=True, 서빙 Pod Running (2/2 컨테이너)
- [ ] 환경변수 설정: `MODEL_NS`, `MODEL_NAME`, `S3_BUCKET`
- [ ] GPU 2기 이상 가용 (멀티 레플리카 / 노드 페일오버 실증 시 필요)

## 실행

### 1. 현재 서빙 상태 확인

~~~bash
# 현재 replica 수 및 Pod 상태 확인
oc get deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} \
  -o jsonpath='replicas={.spec.replicas}'
echo ""

oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --field-selector=status.phase=Running
# 기대: 1개 Pod, Running, 2/2 Ready
~~~

### 2. Pod 장애복구 테스트

~~~bash
# 현재 서빙 Pod 이름 확인
VLLM_POD=$(oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
echo "삭제 대상: ${VLLM_POD}"
echo "삭제 시각: $(date '+%Y-%m-%d %H:%M:%S')"

# Pod 강제 삭제 + 복구 시간 측정
START=$(date +%s)
oc delete pod ${VLLM_POD} -n ${MODEL_NS}

# 새 Pod Ready 대기 (5초 간격 관찰, 최대 3분)
for i in $(seq 1 36); do
  RUNNING=$(oc get pods -n ${MODEL_NS} \
    -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
    --no-headers | grep Running | wc -l)
  echo "$(date '+%H:%M:%S') | Running pods: ${RUNNING}"
  if [[ "$RUNNING" -ge 1 ]]; then break; fi
  sleep 5
done

oc wait pod -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --for=condition=Ready --timeout=300s
END=$(date +%s)
echo "Pod 복구 시간: $((END - START))초"

# API 복구 확인 (Route 경유 — 내부 svc URL은 외부 접근 불가)
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} \
  -o jsonpath='{.spec.host}')
curl -sk -o /dev/null -w "HTTP: %{http_code}\n" "https://${ROUTE}/v1/models"
# 기대: HTTP 200
~~~

### 3. RollingUpdate 무중단 교체

~~~bash
ROUTE=$(oc get route -n ${MODEL_NS} -o jsonpath='{.items[0].spec.host}')

# 별도 터미널: 60초간 연속 요청 (다운타임 측정)
echo "60초간 연속 요청 (다운타임 측정)..."
for i in $(seq 1 60); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 \
    "https://${ROUTE}/v1/models" 2>/dev/null)
  echo "$(date '+%H:%M:%S') HTTP ${CODE}"
  sleep 1
done &
REQ_PID=$!

# 5초 후 롤링 업데이트 트리거 (annotation 변경)
sleep 5
oc patch deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"rollout-trigger\":\"$(date +%s)\"}}}}}"

# 롤링 업데이트 상태 관찰
oc rollout status deployment/${MODEL_NAME}-predictor -n ${MODEL_NS}

wait $REQ_PID
echo "전체 60초 중 HTTP 200 외 응답이 0건이면 PASS"
~~~

### 4. 노드 장애 시 페일오버 (멀티 노드 환경)

~~~bash
# GPU 노드 확인
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}: gpu={.status.capacity.nvidia\.com/gpu}{"\n"}{end}'

# Deployment 스케줄링/tolerations 설정 확인
oc get deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} \
  -o jsonpath='{.spec.template.spec.tolerations}' 2>/dev/null
echo ""

# [멀티 노드 환경에서만 실행]
# GPU_NODE=<대상 노드 이름>
# oc adm cordon ${GPU_NODE}
# oc adm drain ${GPU_NODE} --ignore-daemonsets --delete-emptydir-data --timeout=120s
# -> 다른 노드에서 Pod 재생성 확인
# oc adm uncordon ${GPU_NODE}   # 원복
~~~

> 싱글 워커 노드 환경에서는 페일오버를 실증할 수 없다. K8s 기본 메커니즘(NotReady 축출 + 재스케줄링)은 보장되므로, 멀티 노드(HGX) 환경에서 검증한다.

### 5. 모델 버전 롤백

~~~bash
# 현재 모델 버전(storageUri) 확인
oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  -o jsonpath='{.spec.predictor.model.storageUri}'
echo ""

# 현재 IS 백업
oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} -o yaml \
  > is-backup-${MODEL_NAME}-$(date +%Y%m%d%H%M).yaml
echo "[1/4] 현재 IS 백업 완료"

# 이전 버전으로 롤백 (storage.path 변경 — RHOAI 3.4+ 방식)
oc patch inferenceservice ${MODEL_NAME} -n ${MODEL_NS} --type=merge -p '{
  "spec": {
    "predictor": {
      "model": {
        "storage": {
          "path": "'${MODEL_NAME}'/v1"
        }
      }
    }
  }
}'
echo "[2/4] storage.path 변경 완료"

# Ready 대기
echo "[3/4] Ready 대기 중..."
oc wait inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  --for=condition=Ready --timeout=300s

echo "[4/4] 롤백 후 검증"
oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
echo ""
~~~

## 검증

~~~bash
# Pod 복구 확인 — 새 Pod 이름이 이전과 다른지 확인
NEW_POD=$(oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
echo "현재 Pod: ${NEW_POD}"

# API 응답 확인 (Route 경유)
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} \
  -o jsonpath='{.spec.host}')
curl -sk -o /dev/null -w "HTTP: %{http_code}\n" "https://${ROUTE}/v1/models"
# 기대: HTTP 200

# 추론 응답 확인 (롤백 후)
curl -sk "https://${ROUTE}/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'${MODEL_NAME}'","prompt":"Hello","max_tokens":20}' \
  | python3 -m json.tool
# 기대: 정상 추론 응답
~~~

## 실패 시

- **Pod 미재생 (5분 초과)** → ReplicaSet 이벤트 확인: `oc describe rs -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME}`. GPU 리소스 부족 시 Pending 지속 가능.
- **RollingUpdate 중 다운타임** → replica=1 환경에서는 잠깐의 다운타임 발생 가능. replica=2 이상에서 무중단 보장. `maxSurge`/`maxUnavailable` 전략 확인.
- **노드 drain 후 Pod 미재생** → 다른 노드에 GPU가 있는지 확인: `oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}: gpu={.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'`.
- **롤백 후 Ready=False** → IS 이벤트 확인: `oc describe inferenceservice ${MODEL_NAME} -n ${MODEL_NS}`. storageUri 경로가 유효한지 S3 버킷 확인.
- **Pod 복구 시간 과다** → SmolLM2-135M(경량) 기준 약 2분. 대형 모델(70B+)은 5분 이상 소요. 모델 이미지 캐싱(PVC/S3 로컬 캐시)으로 단축 가능.

## 다음 단계

→ `runbooks/340-scale-to-zero.md` — 미사용 시 자원 회수 (Scale-to-Zero)
