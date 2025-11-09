#!/bin/bash
set -euo pipefail

echo "=== Installing Bare Metal Operator (BMO) ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="baremetal-operator-system"
BMO_VERSION="v0.11.0"

# Check if git is installed (required for kubectl kustomize with remote URLs)
if ! command -v git &>/dev/null; then
    echo "Git is not installed. Installing git..."
    sudo dnf install -y git
fi

# Check if BMO is already deployed
if kubectl get deployment -n "${NAMESPACE}" baremetal-operator-controller-manager &>/dev/null; then
    echo "BMO deployment already exists, checking status..."
    kubectl get deployment -n "${NAMESPACE}" baremetal-operator-controller-manager
    kubectl get pods -n "${NAMESPACE}" -l control-plane=controller-manager
    exit 0
fi

# Step 1: Get the Ironic credential secret name from the Ironic resource
echo "Getting Ironic credential secret name from Ironic resource..."
IRONIC_CRED_SECRET=$(kubectl get ironic/ironic -n "${NAMESPACE}" --template='{{.spec.apiCredentialsName}}' 2>/dev/null)

if [ -z "${IRONIC_CRED_SECRET}" ]; then
    echo "ERROR: Could not find Ironic credential secret name in Ironic resource"
    echo "Please ensure Ironic is deployed first (step 04)"
    exit 1
fi

echo "  Found Ironic credential secret: ${IRONIC_CRED_SECRET}"

# Step 2: Verify the secret exists
if ! kubectl get secret -n "${NAMESPACE}" "${IRONIC_CRED_SECRET}" &>/dev/null; then
    echo "ERROR: Secret ${IRONIC_CRED_SECRET} does not exist in namespace ${NAMESPACE}"
    exit 1
fi

echo "  Verified secret exists"

# Step 3: Verify TLS secret exists
if ! kubectl get secret -n "${NAMESPACE}" ironic-tls &>/dev/null; then
    echo "ERROR: TLS secret 'ironic-tls' does not exist"
    echo "Please run step 03a to create the TLS certificate first"
    exit 1
fi

echo "  Verified TLS secret exists"

# Step 4: Get Ironic endpoint information
IRONIC_IP=$(kubectl get ironic/ironic -n "${NAMESPACE}" -o jsonpath='{.spec.networking.ipAddress}')
IRONIC_API_PORT=$(kubectl get ironic/ironic -n "${NAMESPACE}" -o jsonpath='{.spec.networking.apiPort}')
IRONIC_HTTP_PORT=$(kubectl get ironic/ironic -n "${NAMESPACE}" -o jsonpath='{.spec.networking.imageServerPort}')

echo "  Ironic IP: ${IRONIC_IP}"
echo "  Ironic API Port: ${IRONIC_API_PORT}"
echo "  Ironic HTTP Port: ${IRONIC_HTTP_PORT}"

# Step 5: Create temporary directory for kustomization
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo ""
echo "Creating BMO kustomization in ${TEMP_DIR}..."

# Step 6: Create ironic.env file
cat > "${TEMP_DIR}/ironic.env" <<EOF
DEPLOY_KERNEL_URL=http://${IRONIC_IP}:${IRONIC_HTTP_PORT}/images/ironic-python-agent.kernel
DEPLOY_RAMDISK_URL=http://${IRONIC_IP}:${IRONIC_HTTP_PORT}/images/ironic-python-agent.initramfs
IRONIC_ENDPOINT=https://${IRONIC_IP}:${IRONIC_API_PORT}/v1/
IRONIC_CACERT_FILE=/opt/metal3/certs/ca/tls.crt
IRONIC_INSECURE=false
EOF

echo "  Created ironic.env with Ironic endpoints"

# Step 7: Extract credentials from the secret to create credential files
echo "  Extracting Ironic credentials..."
kubectl get secret -n "${NAMESPACE}" "${IRONIC_CRED_SECRET}" -o jsonpath='{.data.username}' | base64 -d > "${TEMP_DIR}/ironic-username"
kubectl get secret -n "${NAMESPACE}" "${IRONIC_CRED_SECRET}" -o jsonpath='{.data.password}' | base64 -d > "${TEMP_DIR}/ironic-password"

# Step 8: Create kustomization.yaml
cat > "${TEMP_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

# Base BMO configuration from upstream
resources:
- https://github.com/metal3-io/baremetal-operator/config/base?ref=${BMO_VERSION}

# Components for basic-auth and TLS
components:
- https://github.com/metal3-io/baremetal-operator/config/components/basic-auth?ref=${BMO_VERSION}
- https://github.com/metal3-io/baremetal-operator/config/components/tls?ref=${BMO_VERSION}

# Set BMO image version
images:
- name: quay.io/metal3-io/baremetal-operator
  newTag: ${BMO_VERSION}

# Create ConfigMap from ironic.env
configMapGenerator:
- name: ironic
  behavior: create
  envs:
  - ironic.env

# We cannot use suffix hashes since the upstream kustomizations
# cannot be aware of what suffixes we add
generatorOptions:
  disableNameSuffixHash: true

# Create secrets with the credentials for accessing Ironic
secretGenerator:
- name: ironic-credentials
  files:
  - username=ironic-username
  - password=ironic-password

# Patch to use the existing ironic-tls secret for CA certificate
patches:
- target:
    kind: Deployment
    name: baremetal-operator-controller-manager
  patch: |-
    - op: replace
      path: /spec/template/spec/volumes/0/secret/secretName
      value: ironic-tls
EOF

echo "  Created kustomization.yaml"

# Step 9: Display the configuration
echo ""
echo "BMO Configuration Summary:"
echo "  BMO Version: ${BMO_VERSION}"
echo "  Namespace: ${NAMESPACE}"
echo "  Ironic Credentials Secret: ${IRONIC_CRED_SECRET}"
echo "  Ironic TLS Secret: ironic-tls"
echo "  Ironic Endpoint: https://${IRONIC_IP}:${IRONIC_API_PORT}/v1/"
echo ""

# Step 10: Apply the kustomization
echo "Applying BMO kustomization..."
kubectl apply -k "${TEMP_DIR}"

# Step 11: Wait for BMO to become ready
echo ""
echo "Waiting for BMO deployment to become ready (this may take a few minutes)..."
kubectl wait --for=condition=Available --timeout=5m -n "${NAMESPACE}" deployment/baremetal-operator-controller-manager

echo ""
echo "=== BMO Installation Complete ==="
echo ""
echo "BMO status:"
kubectl get deployment -n "${NAMESPACE}" baremetal-operator-controller-manager
echo ""
echo "BMO pods:"
kubectl get pods -n "${NAMESPACE}" -l control-plane=controller-manager
echo ""
echo "BMO is now managing BareMetalHost resources."
echo "You can create BareMetalHost CRDs to register bare-metal machines."
