# 62-b — CPU 기반 HPA 실 스케일업 (No.21)

## 목적

GPU 부족 환경에서 CPU 워크로드로 실제 Pod 1→2→3 스케일업을 실증. HPA 메커니즘은 GPU 모델과 동일.

## 전제 조건

- [ ] CMA(KEDA) Operator 설치 완료
- [ ] 환경변수: `POC_NAMESPACE`

## 실행

### 1. CPU 워크로드 배포

~~~bash
oc apply -n ${POC_NAMESPACE} -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-hpa-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cpu-hpa
  template:
    metadata:
      labels:
        app: cpu-hpa
    spec:
      containers:
        - name: stress
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command: ["sh","-c","while true; do dd if=/dev/urandom bs=1M count=10 of=/dev/null 2>/dev/null; done"]
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
EOF
~~~

### 2. HPA 생성

~~~bash
oc autoscale deployment cpu-hpa-test -n ${POC_NAMESPACE} --min=1 --max=3 --cpu-percent=50
~~~

### 3. 스케일업 대기 및 확인

~~~bash
sleep 90
oc get hpa -n ${POC_NAMESPACE}
oc get pods -n ${POC_NAMESPACE} -l app=cpu-hpa
~~~

## 실측 결과 (2026-05-16)

| 항목 | 결과 |
|------|------|
| CPU 사용률 | 250%/50% |
| Replicas | **1 → 3** |
| 소요 | ~90초 |

## 검증

| 항목 | 기준 | 판정 |
|------|------|------|
| 초기 Pod | 1개 | -- |
| 부하 후 Pod | 2~3개 | **PASS (3개)** |

## 정리

~~~bash
oc delete deployment cpu-hpa-test -n ${POC_NAMESPACE} --ignore-not-found
oc delete hpa cpu-hpa-test -n ${POC_NAMESPACE} --ignore-not-found
~~~

## 다음 단계
→ `runbooks/72-autoscaling-validation.md`
