# Kubernetes Utilities

Kubernetes management utilities for k3s cluster administration and maintenance.

## Scripts

### `delete_all_pods.sh`
Emergency pod cleanup utility for k3s Kubernetes clusters.

**Features:**
- Safely removes all pods from all namespaces
- Handles stuck or problematic pods
- Force deletion for pods that won't terminate gracefully
- Preserves system namespaces when appropriate

**Usage:**
```bash
# Check current pod status first
kubectl get pods --all-namespaces

# Delete all pods (use with caution)
./delete_all_pods.sh
```

**⚠️ Warning:** This script will delete ALL pods in your k3s cluster. Use only in development environments or for emergency cluster recovery.

## Safety Guidelines

1. **Development Only:** Never use in production environments
2. **Backup Critical Data:** Ensure all important data is backed up
3. **Check First:** Always review current pods before deletion
4. **Emergency Use:** Primarily for stuck deployments or cluster recovery
5. **Understand Impact:** Pods will be recreated by their controllers (Deployments, StatefulSets, etc.)

## Integration with k3s Setup

This utility is designed to work with the k3s installation from the main `ubuntu-server-setup.sh` script:

```bash
# After k3s installation, you can use kubectl
kubectl get nodes
kubectl get pods --all-namespaces

# Emergency pod cleanup if needed
./delete_all_pods.sh

# Verify cluster recovery
kubectl get pods --all-namespaces
```

## Common Use Cases

- **Stuck Deployments:** When pods are stuck in terminating or pending state
- **Development Reset:** Clean slate for development testing
- **Troubleshooting:** Clear problematic pods for cluster diagnostics
- **Resource Issues:** Force cleanup when cluster is unresponsive

## Recovery Process

After running the pod deletion script:

1. **Wait for Recreation:** Most pods will be automatically recreated by their controllers
2. **Check System Pods:** Ensure system pods (kube-system namespace) are healthy
3. **Verify Services:** Check that services are responding correctly
4. **Monitor Logs:** Use `kubectl logs` to check for any issues

```bash
# Monitor pod recreation
watch kubectl get pods --all-namespaces

# Check specific namespace
kubectl get pods -n kube-system

# View logs for troubleshooting
kubectl logs -n kube-system -l k8s-app=kube-dns
```