#!/bin/bash
set -euo pipefail

echo "=== Installing cert-manager ==="

# Check if cert-manager is already installed
if kubectl get namespace cert-manager &>/dev/null; then
    echo "cert-manager namespace already exists, checking deployment..."
    if kubectl get deployment -n cert-manager cert-manager &>/dev/null; then
        echo "cert-manager is already installed"
        kubectl get pods -n cert-manager
        exit 0
    fi
fi

# Install cert-manager (latest version)
echo "Installing cert-manager v1.19.1..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml

# Wait for cert-manager to be ready
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-cainjector -n cert-manager

echo ""
echo "=== cert-manager Installation Complete ==="
kubectl get pods -n cert-manager
