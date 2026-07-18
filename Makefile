.PHONY: preflight diff deploy status mirror-list validate tag help
.DEFAULT_GOAL := help

# ──────────────────────────────────────────────
# 환경 변수 로드
# ──────────────────────────────────────────────
ENV_FILE ?= .env
ifneq (,$(wildcard $(ENV_FILE)))
  include $(ENV_FILE)
  export
endif

# ──────────────────────────────────────────────
# help
# ──────────────────────────────────────────────
help:
	@echo "=== openshift-ai-gitops PoC Makefile ==="
	@echo ""
	@echo "  make preflight    환경 검증 (oc, 클러스터 접속, 권한)"
	@echo "  make diff         선언 상태 vs 실제 상태 비교"
	@echo "  make deploy       런북 순서대로 oc apply -k 실행"
	@echo "  make status       전체 PoC 상태 출력"
	@echo "  make mirror-list  에어갭용 이미지 목록 추출"
	@echo "  make validate     S1~S6 선택적 검증"
	@echo "  make tag          고객별 Git 태그 생성"
	@echo ""
	@echo "사전 준비:  cp .env.example .env && vi .env"

# ──────────────────────────────────────────────
# preflight — 환경 검증
# ──────────────────────────────────────────────
preflight:
	@echo "=== Preflight 점검 ==="
	@echo ""
	@echo "[1/5] oc CLI 확인..."
	@oc version --client | head -1
	@echo ""
	@echo "[2/5] 클러스터 접속 확인..."
	@oc whoami || { echo "[FAIL] 클러스터 로그인 필요: oc login"; exit 1; }
	@oc whoami --show-server
	@echo ""
	@echo "[3/5] 권한 확인..."
	@oc auth can-i get nodes > /dev/null 2>&1 && echo "  nodes: OK" || echo "  nodes: [WARN] 읽기 권한 없음"
	@oc auth can-i create namespaces > /dev/null 2>&1 && echo "  namespaces: OK" || echo "  namespaces: [WARN] 생성 권한 없음"
	@echo ""
	@echo "[4/5] OpenShift 버전..."
	@oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null; echo ""
	@echo ""
	@echo "[5/5] GPU 감지..."
	@if [ "$(GPU)" = "auto" ]; then \
		GPU_NODES=$$(oc get nodes -l nvidia.com/gpu.present=true -o name 2>/dev/null | wc -l | tr -d ' '); \
		if [ "$$GPU_NODES" -gt 0 ]; then \
			GPU_MODEL=$$(oc get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.product}' 2>/dev/null); \
			echo "  GPU 노드: $$GPU_NODES개 ($$GPU_MODEL)"; \
		else \
			echo "  GPU 노드: 없음"; \
		fi; \
	else \
		echo "  GPU 설정: $(GPU)"; \
	fi
	@echo ""
	@echo "=== Preflight 완료 ==="

# ──────────────────────────────────────────────
# status — 전체 PoC 상태 출력
# ──────────────────────────────────────────────
status:
	@echo "=== PoC 상태 ($(CUSTOMER) / $$(date +%Y-%m-%d)) ==="
	@echo ""
	@echo "[Operators]"
	@oc get csv -A --no-headers 2>/dev/null | grep -c "Succeeded" | xargs -I{} echo "  Succeeded: {}"
	@oc get csv -A --no-headers 2>/dev/null | grep -v "Succeeded" | grep -v "^$$" | while read line; do echo "  [WARN] $$line"; done || true
	@echo ""
	@echo "[DataScienceCluster]"
	@oc get datasciencecluster -o jsonpath='{range .items[*]}{.metadata.name}: Ready={.status.conditions[?(@.type=="Available")].status}{"\n"}{end}' 2>/dev/null || echo "  미설치"
	@echo ""
	@echo "[InferenceService]"
	@oc get inferenceservice -A --no-headers 2>/dev/null || echo "  없음"
	@echo ""
	@echo "[Pods — 비정상]"
	@UNHEALTHY=$$(oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | grep -E "redhat-ods|rhoai|poc" | head -10); \
	if [ -n "$$UNHEALTHY" ]; then echo "$$UNHEALTHY"; else echo "  모든 관련 Pod 정상"; fi
	@echo ""
	@echo "[ScaledObject]"
	@oc get scaledobject -A --no-headers 2>/dev/null || echo "  없음"
	@echo ""
	@echo "[Pipeline — 최근 실행]"
	@oc get pipelinerun -A --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tail -3 || echo "  없음"
	@echo ""
	@echo "=== 끝 ==="

# ──────────────────────────────────────────────
# diff — 선언 상태 vs 실제 상태 비교
# ──────────────────────────────────────────────
INFRA_DIRS := infra/rhoai infra/operators/job-set infra/operators/leader-worker-set \
              infra/operators/coo infra/operators/tempo infra/operators/otel \
              infra/poc/llm-cpu infra/poc/monitoring infra/poc/network \
              infra/poc/autoscaling infra/poc/guardrails infra/poc/rate-limit \
              infra/poc/workbench-smoke infra/rhoai/gateway infra/rhoai/observability \
              infra/rhoai/dashboards infra/rhoai/evalhub

diff:
	@echo "=== 선언 vs 실제 상태 비교 ==="
	@DIFF_COUNT=0; \
	for dir in $(INFRA_DIRS); do \
		if [ -d "$$dir" ]; then \
			echo ""; \
			echo "--- $$dir ---"; \
			oc diff -k "$$dir" 2>/dev/null && echo "  일치" || DIFF_COUNT=$$((DIFF_COUNT + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "=== 비교 완료 (차이 발견: $$DIFF_COUNT개 디렉토리) ==="

# ──────────────────────────────────────────────
# mirror-list — 에어갭용 이미지 목록 추출
# ──────────────────────────────────────────────
MIRROR_LIST_FILE ?= mirror-images.txt

mirror-list:
	@echo "=== 에어갭 이미지 목록 추출 ==="
	@echo ""
	@echo "[1/3] infra/ YAML에서 image: 참조 추출..."
	@find infra/ -name "*.yaml" -exec grep -h "image:" {} \; 2>/dev/null \
		| sed 's/.*image: *//; s/"//g; s/'"'"'//g' \
		| grep -v "^$$" \
		| sort -u > $(MIRROR_LIST_FILE)
	@echo ""
	@echo "[2/3] Operator 카탈로그 이미지 추가..."
	@echo "# --- Operator 카탈로그 (oc adm catalog mirror 대상) ---" >> $(MIRROR_LIST_FILE)
	@echo "registry.redhat.io/redhat/redhat-operator-index:v$(OCP_VERSION)" >> $(MIRROR_LIST_FILE)
	@echo ""
	@echo "[3/3] 결과 — $(MIRROR_LIST_FILE)"
	@echo "  이미지 수: $$(wc -l < $(MIRROR_LIST_FILE) | tr -d ' ')"
	@echo ""
	@cat $(MIRROR_LIST_FILE)
	@echo ""
	@echo "=== 에어갭 미러링 명령어 ==="
	@echo "  oc image mirror -f $(MIRROR_LIST_FILE) --dest-registry=$(AIRGAP_MIRROR_REGISTRY)"

# ──────────────────────────────────────────────
# deploy — 런북 순서대로 oc apply -k
# ──────────────────────────────────────────────
deploy:
	@echo "=== PoC 배포 시작 ($(CUSTOMER)) ==="
	@echo ""
	@echo "[Step 1] RHOAI Operator..."
	@oc apply -k infra/rhoai/ 2>/dev/null && echo "  OK" || echo "  [SKIP] 이미 적용됨 또는 오류"
	@echo ""
	@echo "[Step 2] Dependency Operators..."
	@for dir in infra/operators/*/; do \
		echo "  $$(basename $$dir)"; \
		oc apply -k "$$dir" 2>/dev/null && echo "    OK" || echo "    [SKIP]"; \
	done
	@echo ""
	@echo "[Step 3] Gateway..."
	@oc apply -k infra/rhoai/gateway/ 2>/dev/null && echo "  OK" || echo "  [SKIP]"
	@echo ""
	@echo "[Step 4] Observability + Dashboards..."
	@oc apply -k infra/rhoai/observability/ 2>/dev/null && echo "  observability OK" || echo "  [SKIP]"
	@oc apply -k infra/rhoai/dashboards/ 2>/dev/null && echo "  dashboards OK" || echo "  [SKIP]"
	@echo ""
	@echo "[Step 5] PoC 리소스..."
	@for dir in infra/poc/*/; do \
		echo "  $$(basename $$dir)"; \
		oc apply -k "$$dir" 2>/dev/null && echo "    OK" || echo "    [SKIP]"; \
	done
	@echo ""
	@echo "[Step 6] EvalHub..."
	@oc apply -k infra/rhoai/evalhub/ 2>/dev/null && echo "  OK" || echo "  [SKIP]"
	@echo ""
	@echo "=== 배포 완료 — 'make status'로 상태 확인 ==="

# ──────────────────────────────────────────────
# validate — S1~S6 선택적 검증
# ──────────────────────────────────────────────
validate:
	@echo "=== PoC 검증 (대상: $(SCENARIOS)) ==="
	@echo ""
	@PASS=0; FAIL=0; SKIP=0; \
	\
	if echo "$(SCENARIOS)" | grep -q "S1"; then \
		echo "[S1] 모델 서빙 검증..."; \
		IS_READY=$$(oc get inferenceservice -A -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); \
		if [ "$$IS_READY" = "True" ]; then echo "  PASS"; PASS=$$((PASS+1)); else echo "  FAIL"; FAIL=$$((FAIL+1)); fi; \
	else SKIP=$$((SKIP+1)); fi; \
	\
	if echo "$(SCENARIOS)" | grep -q "S2"; then \
		echo "[S2] Pipeline 검증..."; \
		LAST_RUN=$$(oc get pipelinerun -A --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].status.conditions[0].reason}' 2>/dev/null); \
		if [ "$$LAST_RUN" = "Succeeded" ]; then echo "  PASS"; PASS=$$((PASS+1)); else echo "  FAIL ($$LAST_RUN)"; FAIL=$$((FAIL+1)); fi; \
	else SKIP=$$((SKIP+1)); fi; \
	\
	if echo "$(SCENARIOS)" | grep -q "S3"; then \
		echo "[S3] Auto-scaling 검증..."; \
		SO_READY=$$(oc get scaledobject -A -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); \
		if [ "$$SO_READY" = "True" ]; then echo "  PASS"; PASS=$$((PASS+1)); else echo "  FAIL"; FAIL=$$((FAIL+1)); fi; \
	else SKIP=$$((SKIP+1)); fi; \
	\
	if echo "$(SCENARIOS)" | grep -q "S4"; then \
		echo "[S4] 장애복구 검증..."; \
		REPLICAS=$$(oc get inferenceservice -A -o jsonpath='{.items[0].status.components.predictor.readyReplicas}' 2>/dev/null); \
		if [ -n "$$REPLICAS" ] && [ "$$REPLICAS" -ge 1 ]; then echo "  PASS (replicas=$$REPLICAS)"; PASS=$$((PASS+1)); else echo "  FAIL"; FAIL=$$((FAIL+1)); fi; \
	else SKIP=$$((SKIP+1)); fi; \
	\
	if echo "$(SCENARIOS)" | grep -q "S5"; then \
		echo "[S5] Scale-to-Zero 검증..."; \
		echo "  [INFO] 수동 검증 필요 (런북 74 참조)"; SKIP=$$((SKIP+1)); \
	else SKIP=$$((SKIP+1)); fi; \
	\
	if echo "$(SCENARIOS)" | grep -q "S6"; then \
		echo "[S6] 운영관리 검증..."; \
		SM_COUNT=$$(oc get servicemonitor -A --no-headers 2>/dev/null | wc -l | tr -d ' '); \
		if [ "$$SM_COUNT" -ge 1 ]; then echo "  PASS (ServiceMonitor: $$SM_COUNT)"; PASS=$$((PASS+1)); else echo "  FAIL"; FAIL=$$((FAIL+1)); fi; \
	else SKIP=$$((SKIP+1)); fi; \
	\
	echo ""; \
	echo "=== 결과: PASS=$$PASS  FAIL=$$FAIL  SKIP=$$SKIP ==="

# ──────────────────────────────────────────────
# tag — 고객별 Git 태그 생성
# ──────────────────────────────────────────────
tag:
	@if [ "$(CUSTOMER)" = "default" ]; then \
		echo "[ERROR] CUSTOMER 변수를 설정하세요: make tag CUSTOMER=customer-poc-v1"; \
		exit 1; \
	fi
	@TAG_NAME="poc/$(CUSTOMER)/$$(date +%Y%m%d)"; \
	echo "=== Git 태그 생성: $$TAG_NAME ==="; \
	git tag -a "$$TAG_NAME" -m "PoC snapshot: $(CUSTOMER) ($$(date +%Y-%m-%d))"; \
	echo "  태그 생성 완료: $$TAG_NAME"; \
	echo "  push: git push origin $$TAG_NAME"
