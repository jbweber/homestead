#!/bin/bash
set -euo pipefail

# Health check script for Cluster API installation and deployed clusters
# Usage: ./validate-health.sh

# Set kubeconfig if not already set
if [ -z "${KUBECONFIG:-}" ]; then
  export KUBECONFIG=~/projects/environment-files/kubeconfig-metal3.yaml
fi

echo "==========================================="
echo "Cluster API Health Check"
echo "==========================================="
echo ""

echo "=== Management Cluster ==="
kubectl get nodes
echo ""

echo "=== CAPI Core Controller ==="
kubectl get deployments -n capi-system
echo ""

echo "=== Kubeadm Bootstrap Provider ==="
kubectl get deployments -n capi-kubeadm-bootstrap-system
echo ""

echo "=== Kubeadm Control Plane Provider ==="
kubectl get deployments -n capi-kubeadm-control-plane-system
echo ""

echo "=== Metal3 Infrastructure Provider ==="
kubectl get deployments -n capm3-system
echo ""

echo "=== Metal3 IPAM Provider ==="
kubectl get deployments -n metal3-ipam-system
echo ""

echo "=== Bare Metal Operator ==="
kubectl get deployments -n baremetal-operator-system
echo ""

echo "=== cert-manager ==="
kubectl get deployments -n cert-manager
echo ""

echo "=== Installed Providers ==="
kubectl get providers -A
echo ""

echo "=== BareMetalHosts ==="
kubectl get baremetalhosts -A
echo ""

echo "=== Clusters ==="
kubectl get clusters -A
echo ""

# Only show machines if clusters exist
if kubectl get clusters -A --no-headers 2>/dev/null | grep -q .; then
  echo "=== Machines ==="
  kubectl get machines -A
  echo ""

  echo "=== Detailed Cluster Status ==="
  kubectl get clusters -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' | while read namespace cluster_name; do
    if [ -n "$cluster_name" ]; then
      echo "Cluster: $cluster_name (namespace: $namespace)"
      clusterctl describe cluster "$cluster_name" -n "$namespace"
      echo ""
    fi
  done
fi

echo "==========================================="
echo "Health Check Complete"
echo "==========================================="
echo ""
echo "For detailed validation steps, see: VALIDATION.md"
