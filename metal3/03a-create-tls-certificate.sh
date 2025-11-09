#!/bin/bash
set -euo pipefail

echo "=== Creating TLS Certificate for Ironic ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Apply the certificate resources
echo "Creating Issuer and Certificate resources..."
kubectl apply -f "${SCRIPT_DIR}/03a-create-tls-certificate.yaml"

# Wait for the certificate to be ready
echo "Waiting for certificate to be issued (this may take a minute)..."
kubectl wait --for=condition=Ready --timeout=2m -n baremetal-operator-system certificate/ironic-cert

echo ""
echo "=== TLS Certificate Created ==="
echo ""
echo "Certificate status:"
kubectl get certificate -n baremetal-operator-system ironic-cert
echo ""
echo "Secret created:"
kubectl get secret -n baremetal-operator-system ironic-tls
echo ""
echo "You can now proceed with deploying Ironic (step 04)"
