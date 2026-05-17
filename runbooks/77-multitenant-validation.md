# 77 — 멀티테넌트 운영 검증 (S8)

## 목적

팀별 API 키 격리, Rate Limit 429를 검증한다. 구축: `67-multitenant.md`.

## 전제 조건

- [ ] 해당 구축 런북 완료 (66/67/68/69)
- [ ] 환경변수: `MODEL_NS=rhoai-poc`

## 실행

검증 항목의 bash 블록을 순서대로 실행한다.

## 검증 항목

### V-S8-1. 팀별 API Key

~~~bash
oc get secret -n rhoai-poc -l maas.opendatahub.io/api-key=true --no-headers | wc -l
# 기대: 2+  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S8-2. Rate Limit 429

~~~bash
# 67-multitenant.md Step 2 결과
# 기대: Team B 429, Team A 무영향  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S8-3. MaaS API 정상

~~~bash
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --no-headers | grep Running
# 기대: Running  |  결과: [   ] PASS / [   ] FAIL
~~~

## 실패 시

- 리소스 미존재 → 해당 구축 런북 재실행
- Pod 미기동 → `oc describe pod` + `oc logs` 확인

## 다음 단계

→ `runbooks/78-security-gate-validation.md`
