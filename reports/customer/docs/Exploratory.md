# Exploratory: 시나리오 미배정 항목

> 시나리오(S1~S6)에 배정되지 않은 27개 항목의 검증 결과.
> 검증 22 / 부분 검증 5 / 미검증 0
>
> **런북 참조**: runbooks/302-guardrails.md, runbooks/340-scale-to-zero.md

---

## A/B 배포 (1건 -- 검증 1)

### No.7 : A/B 배포 (Canary)

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| 설정 | canaryTrafficPercent=20 |
| InferenceService | Ready 유지 |
| 요청 | 10회 전부 HTTP 200 |
| 원복 | 정상 |

---

## 대형 모델 지원 (4건 -- 검증 3 / 부분 1)

### No.17 : 텐서 병렬화 (TP)

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| HGX(H200) | TP+PP 조합 운영 중 |
| 샌드박스 | qwen3-8b llm-d 동작 확인 |

### No.18 : 파이프라인 병렬화 (PP)

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| HGX(H200) | TP+PP 조합 운영 중 |

### No.19 : 멀티노드 추론

> **판정**: 부분 검증

| 항목 | 값 |
|------|-----|
| HGX 단일 노드 | TP+PP 동작 확인 |
| 멀티노드 | 추가 HGX 확보 시 검증 |

### No.20 : 양자화 모델 지원

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| FP8 동적 양자화 | qwen3-8b-fp8-dynamic 추론 정상 |

---

## 트래픽 라우터 (6건 -- 검증 5 / 부분 1)

### No.30 : 통합 API 게이트웨이

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| MaaS Gateway | 2모델(qwen3-8b, llama) 라우팅 |

### No.31 : 모델별 라우팅

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| HTTPRoute | 2개, 모델별 inference-pool 자동 라우팅 |

### No.32 : 로드밸런싱 전략

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| llm-d router | EndpointPickerConfig |
| 스코어러 | queue-scorer(w=2) + prefix-cache-scorer(w=3) + max-score-picker |

### No.33 : 우선순위 기반 라우팅

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| llm-d plugin | weight 기반 우선순위 |
| AuthPolicy | 4개 인증 차등 |

### No.34 : 폴백 라우팅

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| HTTPRoute | InferencePool + workload-svc 이중 backendRef |

### No.35 : GPU 자원 동적 전환

> **판정**: 부분 검증

| 항목 | 값 |
|------|-----|
| KEDA+EPP | Scale-to-Zero 검증 |
| 자동 복원 | llm-d WVA/activator(DP) 필요 |
| Kueue | 별도 Operator 설치 필요 |

---

## API 키 관리 및 Rate Limit (8건 -- 검증 8)

### No.36 : API 키 발급/폐기

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| 인증 | 401(미인증) / 200(유효키) / 401(무효키) |

### No.37 : 키별 모델 접근 제한

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| AuthPolicy | per-model 인증 동작 |

### No.38 : RPM/RPD 제한

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| RateLimitPolicy | RPM=5 설정 |
| 초과 시 | 6회째 **429 Too Many Requests** |

### No.39 : TPM 제한

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| RateLimitPolicy | counter expression 토큰 기반 제한 가능 |

### No.40 : 동시 요청 제한

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| Limitador | 동시 요청 제한, 429 실측 |

### No.41 : 쿼터 관리

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| counter expression | window 설정 쿼터 관리 가능 |

### No.42 : 쿼터 초과 정책

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| 초과 시 | 429 Too Many Requests 차단 |

### No.58 : API 키별 사용량

> **요청구분**: DS-LLM 운영/관리 | **판정**: 검증

| 항목 | 값 |
|------|-----|
| Total Tokens | 282 |
| Requests | 13 |
| Errors | 0 |
| Success Rate | 100% |
| Active Users | 1 |
| Thanos | authorized_hits/calls{user,subscription,model} 수집 |

---

## 모델 최적화 (3건 -- 검증 3)

### No.71 : 자동 양자화

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| FP8 | qwen3-8b-fp8-dynamic 추론 |
| vLLM | `--quantization` 옵션 지원 |

### No.72 : KV Cache 최적화

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| vLLM | PagedAttention 기본 활성 |
| 메트릭 | GPU KV cache usage 수집 |

### No.74 : 스펙큘레이티브 디코딩

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| vLLM 0.18.0 | SpeculativeConfig 지원 |
| 옵션 | `--speculative-model` / `--num-speculative-tokens` |

---

## 보안 및 컴플라이언스 (2건 -- 부분 2)

### No.75 : PII 필터링/마스킹

> **판정**: 부분 검증

| 항목 | 값 |
|------|-----|
| GuardrailsOrchestrator | 3/3 Running |
| 감지기 | HAP / 프롬프트 인젝션 / 정규식 / 언어 감지 |
| TLS 우회 방안 | Granite Guardian을 클러스터 내부 InferenceService로 배포 + 내부 svc URL(http) 연결 시 TLS 제약 없이 동작 가능 |
| 미배포 사유 | GPU 부족 (L40S x4 전량 할당). HGX(H200)에서 배포+검증 권장 |

> **부분 사유**: 자가서명 TLS 환경에서 외부 Route TLS 검증 실패. Granite Guardian 내부 배포 + 내부 svc URL로 우회 가능하나 GPU 부족으로 미배포.

### No.76 : 콘텐츠 필터링

> **판정**: 부분 검증

| 항목 | 값 |
|------|-----|
| HAP 감지기 | 활성 |
| Granite Guardian | 내부 배포 + 내부 svc URL 사용 시 TLS 불필요. GPU 확보 후 진행 |

---

## 확장 기능 및 리소스 관리 (3건 -- 검증 2 / 부분 1)

### No.77 : 파인튜닝 파이프라인

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| TrainJob | 실행 완료 (PyTorch 2.10.0) |
| ClusterTrainingRuntime | 15개 (CUDA/CPU/ROCm) |
| Trainer Operator | Running |

### No.78 : 모델 평가 (Eval)

> **판정**: 검증

| 항목 | 값 |
|------|-----|
| EvalHub | Ready (5 providers) |
| LMEvalJob | Complete (hellaswag) |
| GuideLLM | Quick Perf Test 204 |

### No.80 : 우선순위 자원 할당

> **요청구분**: 플랫폼 관리 | **판정**: 부분 검증

| 항목 | 값 |
|------|-----|
| Build of Kueue | Operator 설치 필요 |
| DSC kueue | Removed -> 별도 Operator 전환 |

> **부분 사유**: DSC kueue Removed. Build of Kueue Operator 별도 설치 필요.
