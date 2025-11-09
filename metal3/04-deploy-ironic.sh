#!/bin/bash
set -euo pipefail

echo "=== Deploying Ironic ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Ironic is already deployed
if kubectl get ironic -n baremetal-operator-system ironic &>/dev/null; then
    echo "Ironic resource already exists, checking status..."
    kubectl get ironic -n baremetal-operator-system ironic -o wide
    exit 0
fi

# Apply the Ironic resource
echo "Deploying Ironic resource..."
kubectl apply -f "${SCRIPT_DIR}/04-deploy-ironic.yaml"

# Wait for Ironic to become ready
echo "Waiting for Ironic to become ready (this may take several minutes)..."
kubectl wait --for=condition=Ready --timeout=10m -n baremetal-operator-system ironic/ironic

echo ""
echo "=== Ironic Deployment Complete ==="
echo ""
echo "Ironic status:"
kubectl get ironic -n baremetal-operator-system ironic -o wide
echo ""
echo "Ironic pods:"
kubectl get pods -n baremetal-operator-system
echo ""
echo "Ironic credentials are stored in secret:"
SECRET=$(kubectl get ironic/ironic -n baremetal-operator-system --template='{{.spec.apiCredentialsName}}' 2>/dev/null || echo "ironic-credentials")
echo "  Secret name: ${SECRET}"
echo ""
echo "To get credentials:"
echo "  kubectl get secrets/${SECRET} -n baremetal-operator-system -o jsonpath='{.data.username}' | base64 -d"
echo "  kubectl get secrets/${SECRET} -n baremetal-operator-system -o jsonpath='{.data.password}' | base64 -d"
