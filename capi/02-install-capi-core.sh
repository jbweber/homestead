#!/bin/bash
set -euo pipefail

echo "=== Installing Cluster API Core Components ==="

# Check if clusterctl is installed
if ! command -v clusterctl &> /dev/null; then
    echo "Error: clusterctl is not installed"
    echo "Run: homestead/capi/01-install-clusterctl.sh"
    exit 1
fi

# Version to install
CAPI_VERSION="v1.11.3"

echo "Target version: $CAPI_VERSION"
echo ""

# Check if CAPI is already installed
if kubectl get namespace capi-system &> /dev/null; then
    echo "Cluster API core is already installed"
    echo ""
    echo "Current providers:"
    kubectl get providers -A
    echo ""
    echo "To reinstall, delete the existing installation:"
    echo "  clusterctl delete --all"
    exit 0
fi

# Verify Metal3 prerequisites
echo "Verifying prerequisites..."

# Check if kubernetes cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot access Kubernetes cluster"
    echo "Ensure you have a working kubeconfig"
    exit 1
fi

# Check if cert-manager is installed (required by CAPI)
if ! kubectl get namespace cert-manager &> /dev/null; then
    echo "Error: cert-manager is not installed"
    echo "Run: homestead/metal3/02-install-cert-manager.sh"
    exit 1
fi

# Verify cert-manager is ready
if ! kubectl wait --for=condition=Available --timeout=60s \
    deployment/cert-manager -n cert-manager &> /dev/null; then
    echo "Error: cert-manager is not ready"
    exit 1
fi

echo "✓ Kubernetes cluster accessible"
echo "✓ cert-manager installed and ready"
echo ""

# Install CAPI core components
echo "Installing Cluster API core components..."
echo "This may take a few minutes..."
echo ""

clusterctl init \
    --core cluster-api:${CAPI_VERSION} \
    --bootstrap kubeadm:${CAPI_VERSION} \
    --control-plane kubeadm:${CAPI_VERSION}

echo ""
echo "Waiting for CAPI components to be ready..."

# Wait for capi-system namespace
kubectl wait --for=condition=Available --timeout=300s \
    deployment/capi-controller-manager -n capi-system

# Wait for bootstrap provider
kubectl wait --for=condition=Available --timeout=300s \
    deployment/capi-kubeadm-bootstrap-controller-manager -n capi-kubeadm-bootstrap-system

# Wait for control-plane provider
kubectl wait --for=condition=Available --timeout=300s \
    deployment/capi-kubeadm-control-plane-controller-manager -n capi-kubeadm-control-plane-system

echo ""
echo "=== Installation Complete ==="
echo ""

# Display installed providers
echo "Installed providers:"
clusterctl get providers

echo ""
echo "CAPI namespaces:"
kubectl get namespaces | grep capi

echo ""
echo "Next steps:"
echo "  Run: homestead/capi/03-install-metal3-provider.sh"
