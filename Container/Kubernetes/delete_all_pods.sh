#!/bin/bash
# Delete all pods in a namespace to force recreation
set -euo pipefail

usage() {
    echo "Usage: $0 [namespace]" >&2
    echo "Deletes all pods in the specified namespace. Defaults to the active namespace or 'default'." >&2
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
fi

namespace="${1:-}"

if [[ -z "$namespace" ]]; then
    namespace="$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)"
    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is not installed or not in PATH." >&2
    exit 1
fi

if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "Namespace '$namespace' does not exist." >&2
    exit 1
fi

echo "Deleting all pods in namespace '$namespace'..."
kubectl delete pod --all --namespace "$namespace"
