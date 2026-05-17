# 78 — 보안 게이트 검증 (S9)

## 목적

PII/HAP 차단, 정상 통과, RBAC 차등을 검증한다. 구축: `68-security-gate.md`.

## 전제 조건

- [ ] 해당 구축 런북 완료 (66/67/68/69)
- [ ] 환경변수: `MODEL_NS=rhoai-poc`

## 실행

검증 항목의 bash 블록을 순서대로 실행한다.

## 검증 항목

### V-S9-1. Guardrails Running

~~~bash
oc get guardrailsorchestrator -n rhoai-poc --no-headers
oc get pods -n rhoai-poc -l app.kubernetes.io/part-of=trustyai --no-headers | grep Running
# 기대: CR + Pod Running  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-2. PII 차단

~~~bash
# 68-security-gate.md Step 1 결과  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-3. 정상 통과

~~~bash
# 기대: HTTP 200  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S9-4. RBAC 3단계

~~~bash
for USER in admin poc-operator poc-user; do
  echo "${USER}: $(oc auth can-i get inferenceservice -n rhoai-poc --as=${USER})"
done
# 기대: admin=yes, operator=yes, user=yes  |  결과: [   ] PASS / [   ] FAIL
~~~

## 실패 시

- 리소스 미존재 → 해당 구축 런북 재실행
- Pod 미기동 → `oc describe pod` + `oc logs` 확인

## 다음 단계

→ `runbooks/79-mlops-validation.md`
