# 581 — S9 변형 검증: 한국 개인정보 커스텀 감지기

## 목적

커스텀 한국 PII 감지기의 배포 상태, 감지 정확도, GuardrailsOrchestrator 연동을 검증한다. 구축: `runbooks/381-korean-pii-detector.md`.

## 전제 조건

- [ ] `runbooks/381-korean-pii-detector.md` 구축 완료
- [ ] korean-pii-detector Pod Running
- [ ] 환경변수: `MODEL_NS=rhoai-poc`, `MODEL_NAME=smollm2-135m`

## 실행

검증 항목의 bash 블록을 순서대로 실행한다.

## 검증 항목

### V-S9-5-1. 감지기 Pod Running

~~~bash
oc get pods -n ${MODEL_NS} -l app=korean-pii-detector --no-headers
# 기대: 1/1 Running  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-5-2. Health 정상

~~~bash
oc exec -n ${MODEL_NS} deploy/minio -- curl -s \
  "http://korean-pii-detector.${MODEL_NS}.svc.cluster.local:8080/health"
# 기대: {"status":"healthy"}  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-5-3. 주민등록번호 감지

~~~bash
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

### V-S9-5-4. 복합 감지 (주민번호 + 전화번호)

~~~bash
oc exec -n ${MODEL_NS} deploy/minio -- curl -s \
  "http://korean-pii-detector.${MODEL_NS}.svc.cluster.local:8080/api/v1/text/contents" \
  -H "Content-Type: application/json" \
  -d '{"contents":["주민번호 850101-1234567, 전화 010-9876-5432"]}' | python3 -c "
import sys,json
d=json.load(sys.stdin)[0].get('detections',[])
print(f'감지: {len(d)}건')
for x in d: print(f'  {x[\"detection\"]}: {x[\"text\"]}')
"
# 기대: 2건  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-5-5. 정상 텍스트 미감지

~~~bash
oc exec -n ${MODEL_NS} deploy/minio -- curl -s \
  "http://korean-pii-detector.${MODEL_NS}.svc.cluster.local:8080/api/v1/text/contents" \
  -H "Content-Type: application/json" \
  -d '{"contents":["서울의 날씨는 맑습니다"]}' | python3 -c "
import sys,json; print(f'감지: {len(json.load(sys.stdin)[0].get(\"detections\",[]))}건')
"
# 기대: 0건  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-5-6. Guardrails 연동 E2E

~~~bash
GW_SVC="http://${MODEL_NAME}-guardrails-gateway.${MODEL_NS}.svc.cluster.local:8443"
oc exec -n ${MODEL_NS} deploy/minio -- curl -sk "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'${MODEL_NAME}'","messages":[{"role":"user","content":"내 주민번호는 850101-1234567 입니다"}],"max_tokens":30}'
# 기대: 차단  |  결과: [   ] PASS / [   ] FAIL
~~~

## 실패 시

- **Pod 없음** → `381-korean-pii-detector.md` 재실행
- **감지 0건** → 정규식 패턴 확인
- **Guardrails 미연동** → orchestratorConfig 설정 확인

## 다음 단계

→ `runbooks/590-mlops-validation.md`
