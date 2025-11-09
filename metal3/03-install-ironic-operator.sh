#!/bin/bash
set -euo pipefail

echo "=== Installing Ironic Standalone Operator (IrSO) ==="

# Check if IrSO is already installed
if kubectl get namespace ironic-standalone-operator-system &>/dev/null; then
    echo "IrSO namespace already exists, checking deployment..."
    if kubectl get deployment -n ironic-standalone-operator-system ironic-standalone-operator-controller-manager &>/dev/null; then
        echo "IrSO is already installed"
        kubectl get pods -n ironic-standalone-operator-system
        exit 0
    fi
fi

# Install IrSO (latest stable version)
IRSO_VERSION=0.6.0
echo "Installing Ironic Standalone Operator v${IRSO_VERSION}..."
kubectl apply -f https://github.com/metal3-io/ironic-standalone-operator/releases/download/v${IRSO_VERSION}/install.yaml

# Wait for IrSO to be ready
echo "Waiting for IrSO controller to be ready..."
kubectl wait --for=condition=Available --timeout=120s \
  -n ironic-standalone-operator-system deployment/ironic-standalone-operator-controller-manager

echo ""
echo "=== IrSO Installation Complete ==="
kubectl get pods -n ironic-standalone-operator-system
