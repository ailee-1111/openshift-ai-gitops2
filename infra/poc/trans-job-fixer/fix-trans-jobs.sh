#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-customer-poc}"
CA_CONFIGMAP="config-trusted-cabundle"
CA_KEY="ca-bundle.crt"
CA_MOUNT="/etc/pki/tls/certs/custom-ca"
LABEL="modelregistry.kubeflow.org/job-type=async-upload"

echo "[$(date -u +%FT%TZ)] Scanning namespace=$NAMESPACE for failed async-upload jobs..."

JOBS_FILE=$(mktemp /tmp/jobs-XXXXXX.json)
trap 'rm -f "$JOBS_FILE" /tmp/job-fixed.json' EXIT

oc get jobs -n "$NAMESPACE" -l "$LABEL" -o json > "$JOBS_FILE" 2>/dev/null || echo '{"items":[]}' > "$JOBS_FILE"

python3 - "$JOBS_FILE" "$CA_CONFIGMAP" "$CA_KEY" "$CA_MOUNT" "$NAMESPACE" <<'PYEOF'
import json, sys, subprocess, os

jobs_file    = sys.argv[1]
ca_configmap = sys.argv[2]
ca_key       = sys.argv[3]
ca_mount     = sys.argv[4]
namespace    = sys.argv[5]

with open(jobs_file) as f:
    data = json.load(f)

items = data.get("items", [])
if not items:
    print("No async-upload jobs found.")
    sys.exit(0)

fixed = 0
for job in items:
    name = job["metadata"]["name"]
    conditions = job.get("status", {}).get("conditions", [])

    is_failed = any(
        c.get("type") == "Failed" and c.get("status") == "True"
        for c in conditions
    )
    if not is_failed:
        print(f"[SKIP] {name}: not in Failed state")
        continue

    volumes = job["spec"]["template"]["spec"].get("volumes", [])
    if any(v.get("name") == "trusted-ca" for v in volumes):
        print(f"[SKIP] {name}: already has CA volume")
        continue

    print(f"[FIX]  {name}: rebuilding with CA bundle...")

    for key in ["resourceVersion", "uid", "creationTimestamp", "managedFields"]:
        job["metadata"].pop(key, None)
    job["metadata"].get("annotations", {}).pop(
        "kubectl.kubernetes.io/last-applied-configuration", None
    )
    job.pop("status", None)

    job["spec"].pop("selector", None)
    tmpl_meta = job["spec"]["template"].get("metadata", {})
    tmpl_meta.pop("labels", None)

    job["metadata"].setdefault("labels", {})["trans-job-fixer/fixed"] = "true"

    job["spec"]["template"]["spec"].setdefault("volumes", []).append({
        "name": "trusted-ca",
        "configMap": {
            "name": ca_configmap,
            "items": [{"key": ca_key, "path": "ca-bundle.crt"}],
            "optional": True,
        },
    })

    container = job["spec"]["template"]["spec"]["containers"][0]
    container.setdefault("volumeMounts", []).append({
        "name": "trusted-ca",
        "mountPath": ca_mount,
        "readOnly": True,
    })
    container.setdefault("env", []).append({
        "name": "SSL_CERT_FILE",
        "value": f"{ca_mount}/ca-bundle.crt",
    })

    job["spec"]["backoffLimit"] = 3

    tmp = "/tmp/job-fixed.json"
    with open(tmp, "w") as f:
        json.dump(job, f)

    r = subprocess.run(
        ["oc", "delete", "job", name, "-n", namespace,
         "--cascade=foreground", "--wait=true"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        print(f"[ERR]  delete {name}: {r.stderr.strip()}")
        continue

    r = subprocess.run(
        ["oc", "create", "-f", tmp],
        capture_output=True, text=True,
    )
    if r.returncode == 0:
        print(f"[OK]   {name}: recreated with CA bundle")
        fixed += 1
    else:
        print(f"[ERR]  create {name}: {r.stderr.strip()}")

print(f"Fixed {fixed} job(s).")

PYEOF

echo "[$(date -u +%FT%TZ)] Done."
