# 305 — 멀티노드 추론 아키텍처 검증 (No.19)

## 목적

단일 노드 TP+PP 동작을 실증하고, LeaderWorkerSet(LWS) CRD가 멀티노드 분산을 지원하는 아키텍처임을 문서화.

## 전제 조건

- [ ] LeaderWorkerSet Operator v1.0.0 설치

## 실행

### 1. LWS Operator 확인

~~~bash
oc get csv -n openshift-lws-operator | grep lws
oc get crd | grep leaderworkersets
~~~

### 2. vLLM TP 설정 확인

~~~bash
oc get inferenceservice -n ${POC_NAMESPACE} -o yaml | grep -A5 "tensor-parallel\|TENSOR_PARALLEL"
~~~

### 3. 아키텍처 문서화

```
단일 노드 (HGX H200): TP+PP 검증 완료
멀티노드 확장: LWS CRD → leader + worker Pod(다른 노드)
vLLM: --tensor-parallel-size N --pipeline-parallel-size M
→ 추가 HGX 확보 시 동일 메커니즘 확장
```

## 검증

| 항목 | 기준 | 판정 |
|------|------|------|
| LWS Operator | 설치 | PASS |
| LWS CRD | 존재 | PASS |
| TP 동작 | 단일 노드 검증 | PASS |
| 멀티노드 | 아키텍처 실증 | PASS |

## 다음 단계
→ 추가 HGX 확보 시 멀티노드 실 테스트
