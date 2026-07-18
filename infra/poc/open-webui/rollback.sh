#!/bin/bash
set -euo pipefail
# chatbot 별칭 + thinking 비활성화 원복

echo "=== qwen3-8b 원복 ==="
oc patch llminferenceservice qwen3-8b -n customer-poc --type=json -p '[
  {"op":"replace","path":"/spec/template/containers/0/env/0/value",
   "value":"--max-model-len=8192 --gpu-memory-utilization=0.90 --max-num-seqs=8"}
]'

echo "=== qwen35-122b 원복 ==="
oc patch llminferenceservice redhataiqwen35-122b-a10b-fp8-d -n customer-poc --type=json -p '[
  {"op":"replace","path":"/spec/template/containers/0/env/1/value",
   "value":"--tensor-parallel-size=2 --reasoning-parser=qwen3 --language-model-only --max-model-len=96000 --gpu-memory-utilization=0.92 --enable-log-requests --enable-log-outputs"}
]'

echo ""
echo "원복 완료. Pod 롤링 재시작 대기..."
