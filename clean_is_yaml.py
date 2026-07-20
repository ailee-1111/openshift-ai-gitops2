import json
import yaml
import os

def clean_and_convert_yaml():
    # 1. Get raw YAML from cluster
    cmd = "oc get inferenceservice redhataiqwen3-8b-fp8-dynamic -n user1-canopy -o json"
    raw_json = os.popen(cmd).read()
    
    if not raw_json.strip():
        print("Error: Could not retrieve inferenceservice from user1-canopy")
        return
        
    data = json.loads(raw_json)
    
    # 2. Clean read-only metadata fields
    metadata = data.get("metadata", {})
    clean_metadata = {
        "name": "qwen3-8b-fp8-dynamic-demo",
        "namespace": "demo",
        "annotations": {
            k: v for k, v in metadata.get("annotations", {}).items()
            if not any(prefix in k for prefix in ["kubectl.kubernetes.io", "creationTimestamp"])
        },
        "labels": {
            k: v for k, v in metadata.get("labels", {}).items()
        }
    }
    
    # Ensure hardware profile and target model annotations are preserved
    data["metadata"] = clean_metadata
    
    # Clean status and metadata from spec
    if "status" in data:
        del data["status"]
        
    spec = data.get("spec", {})
    if "predictor" in spec:
        predictor = spec["predictor"]
        # Ensure it has exactly 1 GPU limit/request for L40 efficiency, as requested!
        if "model" in predictor and "resources" in predictor["model"]:
            res = predictor["model"]["resources"]
            res["limits"] = {
                "cpu": "2",
                "memory": "8Gi",
                "nvidia.com/gpu": "1" # L40 1-GPU limit!
            }
            res["requests"] = {
                "cpu": "2",
                "memory": "8Gi",
                "nvidia.com/gpu": "1"
            }
            
    # Save the cleaned and restructured YAML
    output_path = "/Users/seunglee/gemini/OpenShift-AI-Gitops/openshift-ai-gitops/infra/poc/model-serving/qwen3-8b-fp8-dynamic-demo.yaml"
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    with open(output_path, "w", encoding="utf-8") as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
        
    print(f"✅ Cleaned InferenceService YAML successfully written to: {output_path}")

if __name__ == "__main__":
    clean_and_convert_yaml()
