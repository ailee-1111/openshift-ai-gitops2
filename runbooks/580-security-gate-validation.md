# 580 — 보안 게이트 검증 (S9)

## 목적

GuardrailsOrchestrator의 PII/HAP 차단, 정상 통과, RBAC 차등을 검증한다. 구축: `runbooks/380-security-gate.md`.

## 전제 조건

- [ ] `runbooks/380-security-gate.md` 구축 완료
- [ ] GuardrailsOrchestrator Pod Running (3/3)
- [ ] 환경변수: `MODEL_NS=rhoai-poc`, `MODEL_NAME=smollm2-135m`

## 실행

검증 항목의 bash 블록을 순서대로 실행한다.

## 검증 항목

### V-S9-1. Guardrails Running

~~~bash
oc get guardrailsorchestrator -n ${MODEL_NS} --no-headers
oc get pods -n ${MODEL_NS} -l app.kubernetes.io/part-of=trustyai --no-headers | grep Running
# 기대: CR 존재 + Pod Running (3/3)  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-2. PII 차단 (SSN)

~~~bash
GW_SVC="http://${MODEL_NAME}-guardrails-gateway.${MODEL_NS}.svc.cluster.local:8443"

echo "=== PII 차단 테스트 ==="
oc exec -n ${MODEL_NS} deploy/minio -- curl -sk "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'${MODEL_NAME}'","messages":[{"role":"user","content":"My SSN is 123-45-6789"}],"max_tokens":30}' 2>/dev/null | \
  python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('error',{}).get('message',r.get('choices',[{}])[0].get('message',{}).get('content',''))[:80])"
# 기대: 차단 응답 (PII 감지)  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-3. 정상 통과

~~~bash
echo "=== 정상 요청 테스트 ==="
HTTP_CODE=$(oc exec -n ${MODEL_NS} deploy/minio -- curl -sk -o /dev/null -w "%{http_code}" \
  "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'${MODEL_NAME}'","messages":[{"role":"user","content":"What is 2+2?"}],"max_tokens":10}' 2>/dev/null)
echo "HTTP: ${HTTP_CODE}"
# 기대: HTTP 200 + 정상 추론  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-4. RBAC 3단계

~~~bash
echo "=== RBAC 검증 ==="
for USER in admin poc-operator poc-user; do
  echo "[${USER}]"
  echo "  IS 읽기: $(oc auth can-i get inferenceservice -n ${MODEL_NS} --as=${USER} 2>/dev/null)"
  echo "  IS 생성: $(oc auth can-i create inferenceservice -n ${MODEL_NS} --as=${USER} 2>/dev/null)"
  echo "  NS 삭제: $(oc auth can-i delete namespace -n ${MODEL_NS} --as=${USER} 2>/dev/null)"
done
# 기대: admin=yes/yes/yes, operator=yes/yes/no, user=yes/no/no
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-5. 한국 PII 감지 (커스텀 감지기)

~~~bash
# 감지기 Pod Running
oc get pods -n ${MODEL_NS} -l app=korean-pii-detector --no-headers
# 기대: 1/1 Running  |  결과: [   ] PASS / [   ] FAIL

# 주민등록번호 감지
oc exec -n ${MODEL_NS} deploy/minio -- curl -s \
  "http://korean-pii-detector.${MODEL_NS}.svc.cluster.local:8080/api/v1/text/contents" \
  -H "Content-Type: application/json" \
  -d '{"contents":["주민번호 850101-1234567"]}' | python3 -c "
import sys,json
d=json.load(sys.stdin)[0].get('detections',[])
print(f'감지: {len(d)}건')
for x in d: print(f'  {x[\"detection\"]}: {x[\"text\"]}')
"
# 기대: 1건 (주민등록번호)  |  결과: [   ] PASS / [   ] FAIL
~~~

## 제약 사항

| 항목 | 내용 |
|------|------|
| TLS | 자가서명 환경에서 외부 Route 경유 불가 → 내부 svc URL(`http://`) 사용 |
| GPU Guardian | Granite Guardian(GPU 기반)이 더 정확하지만 GPU 필요 → v4 Phase K 예정 |
| 한국어 PII | 내장 감지기는 영어 중심. 한국어(주민번호 등)는 커스텀 감지기 추가 필요 |
| HAP 정확도 | 내장 분류 모델 기반. 미묘한 유해 콘텐츠는 오탐/미탐 가능 |

## 실패 시

- **PII 미감지** → `enableBuiltInDetectors: true` 확인
- **TLS 오류** → 내부 svc URL 사용
- **Guardrails CrashLoop** → `oc logs deploy/${MODEL_NAME}-guardrails --all-containers -n ${MODEL_NS}`
- **RBAC 실패** → `oc get rolebinding -n ${MODEL_NS}` 확인

## 다음 단계

→ `runbooks/590-mlops-validation.md`
