#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

PASS=0
FAIL=0

assert_ok() {
    local desc="$1"; shift
    if "$@" > /dev/null 2>&1; then
        echo "  [PASS] $desc"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Makefile 구조 테스트 (클러스터 불필요) ==="
echo ""

assert_ok "Makefile 존재" test -f Makefile

for target in preflight diff deploy status mirror-list validate tag help; do
    assert_ok "타겟 정의: $target" grep -q "^${target}:" Makefile
done

for var in SCENARIOS GPU CUSTOMER KUBECONFIG CLUSTER_DOMAIN; do
    assert_ok ".env.example 변수: $var" grep -q "^${var}=" .env.example
done

assert_ok "make help 실행" make help

make mirror-list AIRGAP_MIRROR_REGISTRY=test.registry OCP_VERSION=4.21 > /dev/null 2>&1 || true
assert_ok "mirror-images.txt 생성" test -f mirror-images.txt
assert_ok "mirror-images.txt 내용 있음" test -s mirror-images.txt
rm -f mirror-images.txt

echo ""
echo "=== 결과: PASS=$PASS  FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
