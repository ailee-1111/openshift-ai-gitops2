#!/bin/bash
set -eo pipefail

echo "=========================================================="
echo "🆕 [Demo Project] 신규 'demo' 프로젝트 및 권한 수립 개시"
echo "=========================================================="

# 1. 신규 'demo' 프로젝트 네임스페이스 생성 (이미 존재하는 경우 Skip)
if ! oc get project demo &>/dev/null; then
  echo "🆕 [Infra] 'demo' 프로젝트 네임스페이스 신설..."
  oc create namespace demo
else
  echo "⏭️  [Skip] 'demo' 네임스페이스가 이미 존재하여 생략합니다."
fi

# 2. user1이 관리자 권한이 되도록 ClusterRole admin 바인딩 (이미 존재하는 경우 Skip)
if ! oc get rolebinding user1-demo-admin -n demo &>/dev/null; then
  echo "🆕 [Permission] user1을 'demo' 네임스페이스의 admin 권한자로 연동 바인딩..."
  oc create rolebinding user1-demo-admin --clusterrole=admin --user=user1 -n demo
else
  echo "⏭️  [Skip] user1-demo-admin 권한 바인딩이 이미 존재하여 생략합니다."
fi

# 3. ServingRuntime 복사본 배포적용 (InferenceService의 엔진 기둥 수립!)
echo "🚀 [Deploy] redhataiqwen3-8b-fp8-dynamic ServingRuntime 배포..."
oc apply -f "/Users/seunglee/gemini/OpenShift-AI-Gitops/openshift-ai-gitops/infra/poc/model-serving/redhataiqwen3-8b-fp8-dynamic-runtime.json"

# 4. L40 최적화 1-GPU Qwen3-8B-FP8-dynamic 데모 모델 배포적용
echo "🚀 [Deploy] 1-GPU Qwen3-8B-FP8-dynamic 데모 모델을 'demo' 공간에 배포 가동..."
oc apply -f "/Users/seunglee/gemini/OpenShift-AI-Gitops/openshift-ai-gitops/infra/poc/model-serving/qwen3-8b-fp8-dynamic-demo.json"

# 5. 배포 수렴 모니터링 기동 (최대 20회, 각 15초 간격으로 진행 추이 추적)
echo "----------------------------------------------------------"
echo "⏱️  Qwen3-8B-FP8-dynamic-demo 모델의 정상 기동 수렴(Ready=True)을 실시간 추적합니다..."
echo "----------------------------------------------------------"

i=1
while [ "$i" -le 20 ]; do
  READY_STATUS=$(oc get inferenceservice qwen3-8b-fp8-dynamic-demo -n demo -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  PHASE=$(oc get inferenceservice qwen3-8b-fp8-dynamic-demo -n demo -o jsonpath='{.status.modelStatus.transitionStatus}' 2>/dev/null || echo "Progressing")
  
  echo "   📊 [Model Serving 상태 - 시도 $i/20] READY=$READY_STATUS, TransitionStatus=$PHASE"
  
  if [ "$READY_STATUS" = "True" ]; then
    echo "🎉 [Success] Qwen3-8B-FP8-dynamic-demo 모델이 'demo' 네임스페이스에 무결 가동되었습니다!"
    oc get inferenceservice qwen3-8b-fp8-dynamic-demo -n demo
    break
  fi
  
  sleep 15
  i=$((i + 1))
done
