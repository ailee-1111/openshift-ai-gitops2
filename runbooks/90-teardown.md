# 90 — Teardown (PoC 종료 후 정리)

## 목적

PoC가 완료된 후 생성된 리소스를 안전하게 정리한다. 기존 워크로드에 영향이 없는지 확인한 뒤 역순으로 삭제하여 클러스터를 PoC 이전 상태로 복원한다.

## 전제 조건

- [ ] PoC 검증 완료 및 리포트 작성 완료
- [ ] 보존할 데이터(모델, 로그, 평가 결과)의 백업 완료
- [ ] 기존 워크로드에 영향이 없는지 관련 팀과 확인
- [ ] 환경변수: `MODEL_NS`

## 실행

### 1. PoC 네임스페이스 삭제

> MinIO, MailHog, InferenceService, GuardrailsOrchestrator, TrustyAI, Pipeline 등 해당 네임스페이스의 모든 리소스가 함께 삭제된다.

~~~bash
# 삭제 전 네임스페이스 내 리소스 확인
oc get all -n ${MODEL_NS}

# 네임스페이스 삭제
oc delete project ${MODEL_NS}

# 삭제 완료 대기
oc wait project/${MODEL_NS} --for=delete --timeout=120s 2>/dev/null || true
~~~

### 2. Observability Operator 정리 (선택)

> Observability 전용 Operator를 더 이상 사용하지 않는 경우에만 삭제한다.

~~~bash
# COO
oc delete subscription cluster-observability-operator \
  -n openshift-cluster-observability-operator --ignore-not-found
oc delete csv -n openshift-cluster-observability-operator --all --ignore-not-found

# Tempo
oc delete subscription tempo-product \
  -n openshift-tempo-operator --ignore-not-found
oc delete csv -n openshift-tempo-operator --all --ignore-not-found

# OpenTelemetry
oc delete subscription opentelemetry-product \
  -n openshift-opentelemetry-operator --ignore-not-found
oc delete csv -n openshift-opentelemetry-operator --all --ignore-not-found
~~~

### 3. PoC 전용 Operator 정리 (선택)

> KEDA, Kuadrant(RHCL), ManualApprovalGate 등 PoC 목적으로만 설치된 Operator를 정리한다.

~~~bash
oc delete subscription custom-metrics-autoscaler \
  -n openshift-keda --ignore-not-found
oc delete subscription rhcl-operator \
  -n kuadrant-system --ignore-not-found

oc delete kedacontroller keda \
  -n openshift-keda --ignore-not-found
oc delete kuadrant kuadrant \
  -n kuadrant-system --ignore-not-found

oc delete manualapprovalgate manual-approval-gate --ignore-not-found
~~~

### 4. OAuth IdP 제거

> htpasswd-poc IdP를 제거한다. 다른 IdP가 등록되어 있다면 인덱스를 정확히 확인한 후 실행한다.

~~~bash
# 현재 등록된 IdP 목록 확인
oc get oauth cluster \
  -o jsonpath='{range .spec.identityProviders[*]}{.name}{"\n"}{end}'

# htpasswd-poc가 index 0인지 확인 후 제거
# 주의: 반드시 올바른 인덱스를 지정할 것
oc patch oauth cluster --type='json' \
  -p '[{"op":"remove","path":"/spec/identityProviders/0"}]'
~~~

### 5. Dashboard replica 원복

~~~bash
oc scale deployment rhods-dashboard \
  -n redhat-ods-applications --replicas=2
~~~

## 검증

~~~bash
# 1) PoC 네임스페이스 삭제 확인
oc get project ${MODEL_NS} 2>&1 | grep -q "not found" \
  && echo "PASS: NS 삭제 완료" || echo "FAIL: NS 잔존"

# 2) PoC 관련 CRD 리소스 잔존 확인
oc get inferenceservice -A 2>/dev/null | grep -v "^NAMESPACE" | head -5
oc get guardrailsorchestrator -A 2>/dev/null | head -5
oc get lmevaljob -A 2>/dev/null | head -5

# 3) OAuth IdP 확인
oc get oauth cluster \
  -o jsonpath='{.spec.identityProviders[*].name}'
# 기대: htpasswd-poc 없음

# 4) Dashboard replica 확인
oc get deployment rhods-dashboard -n redhat-ods-applications \
  -o jsonpath='{.spec.replicas}'
echo ""
# 기대: 2

# 5) 클러스터 전반 상태
oc get clusterversion
oc get nodes --no-headers
oc get co --no-headers | grep -v "True.*False.*False" | head -5
# 기대: ClusterOperator 전체 Available=True
~~~

성공 기준:
- PoC 네임스페이스 완전 삭제
- OAuth에 htpasswd-poc IdP 없음
- Dashboard replica 2로 원복
- 클러스터 전반 정상 (ClusterOperator 전체 Available)

## 실패 시

- **네임스페이스 삭제 Terminating에 멈춤** → finalizer가 남아있는 리소스 확인: `oc get all -n ${MODEL_NS}`. InferenceService, TrustyAIService 등 CRD 리소스의 finalizer를 수동 제거 후 재시도.
- **OAuth 패치 실패 (인덱스 오류)** → `oc get oauth cluster -o yaml`로 identityProviders 배열을 확인하고 정확한 인덱스를 지정. IdP가 1개뿐이면 `identityProviders` 키 자체를 제거.
- **Operator CSV 삭제 후 CRD 잔존** → 개별 CRD 수동 삭제: `oc delete crd <crd-name>`. 단, 해당 CRD를 다른 네임스페이스에서도 사용 중인지 확인 필수.

## 다음 단계

→ PoC 종료. 리포트는 `reports/` 디렉터리 참조.
