#!/bin/bash
set -euo pipefail

echo "=== Verifying Cluster API Installation ==="
echo ""

# Check if clusterctl is installed
if ! command -v clusterctl &> /dev/null; then
    echo "✗ clusterctl is not installed"
    echo "Run: homestead/capi/01-install-clusterctl.sh"
    exit 1
fi

echo "✓ clusterctl is installed"
clusterctl version | grep "clusterctl version"
echo ""

# Check CAPI core namespaces
echo "Checking CAPI namespaces..."
REQUIRED_NAMESPACES=(
    "capi-system"
    "capi-kubeadm-bootstrap-system"
    "capi-kubeadm-control-plane-system"
    "capm3-system"
)

MISSING_NAMESPACES=()
for ns in "${REQUIRED_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        echo "  ✓ $ns"
    else
        echo "  ✗ $ns (missing)"
        MISSING_NAMESPACES+=("$ns")
    fi
done

if [ ${#MISSING_NAMESPACES[@]} -ne 0 ]; then
    echo ""
    echo "Error: Missing required namespaces"
    echo "Run the installation scripts in order:"
    echo "  02-install-capi-core.sh"
    echo "  03-install-metal3-provider.sh"
    exit 1
fi

echo ""

# Check provider installations
echo "Installed providers:"
kubectl get providers -A
echo ""

# Check deployments in each namespace
echo "Checking CAPI deployments..."

# CAPI core
if kubectl wait --for=condition=Available --timeout=10s \
    deployment/capi-controller-manager -n capi-system &> /dev/null; then
    echo "  ✓ capi-controller-manager (capi-system)"
else
    echo "  ✗ capi-controller-manager (capi-system) - not ready"
fi

# Bootstrap provider
if kubectl wait --for=condition=Available --timeout=10s \
    deployment/capi-kubeadm-bootstrap-controller-manager -n capi-kubeadm-bootstrap-system &> /dev/null; then
    echo "  ✓ capi-kubeadm-bootstrap-controller-manager (capi-kubeadm-bootstrap-system)"
else
    echo "  ✗ capi-kubeadm-bootstrap-controller-manager - not ready"
fi

# Control plane provider
if kubectl wait --for=condition=Available --timeout=10s \
    deployment/capi-kubeadm-control-plane-controller-manager -n capi-kubeadm-control-plane-system &> /dev/null; then
    echo "  ✓ capi-kubeadm-control-plane-controller-manager (capi-kubeadm-control-plane-system)"
else
    echo "  ✗ capi-kubeadm-control-plane-controller-manager - not ready"
fi

# Metal3 infrastructure provider
if kubectl wait --for=condition=Available --timeout=10s \
    deployment/capm3-controller-manager -n capm3-system &> /dev/null; then
    echo "  ✓ capm3-controller-manager (capm3-system)"
else
    echo "  ✗ capm3-controller-manager - not ready"
fi

echo ""

# Check Metal3 integration
echo "Checking Metal3 integration..."

# Check BMO namespace
if kubectl get namespace baremetal-operator-system &> /dev/null; then
    echo "  ✓ Bare Metal Operator namespace exists"
else
    echo "  ✗ Bare Metal Operator namespace not found"
    echo "    Install via: homestead/metal3/05-install-bmo.sh"
fi

# Check BareMetalHost CRD
if kubectl get crd baremetalhosts.metal3.io &> /dev/null; then
    echo "  ✓ BareMetalHost CRD installed"

    # Check for available hosts
    AVAILABLE_HOSTS=$(kubectl get baremetalhosts -A -o jsonpath='{range .items[?(@.status.provisioning.state=="available")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | wc -l)
    TOTAL_HOSTS=$(kubectl get baremetalhosts -A --no-headers 2>/dev/null | wc -l)

    echo "  ℹ BareMetalHosts: $TOTAL_HOSTS total, $AVAILABLE_HOSTS available"

    if [ "$AVAILABLE_HOSTS" -gt 0 ]; then
        echo ""
        echo "  Available hosts for cluster creation:"
        kubectl get baremetalhosts -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATE:.status.provisioning.state | grep available || true
    fi
else
    echo "  ✗ BareMetalHost CRD not found"
fi

echo ""

# Check cert-manager
echo "Checking cert-manager..."
if kubectl get namespace cert-manager &> /dev/null; then
    if kubectl wait --for=condition=Available --timeout=10s \
        deployment/cert-manager -n cert-manager &> /dev/null; then
        echo "  ✓ cert-manager is running"
    else
        echo "  ✗ cert-manager is not ready"
    fi
else
    echo "  ✗ cert-manager namespace not found"
fi

echo ""
echo "=== Verification Complete ==="
echo ""
echo "Cluster API is ready to create clusters!"
echo ""
echo "Next steps:"
echo "  1. Create environment variables: ~/projects/environment-files/super-capi-cluster-variables.rc"
echo "  2. Generate cluster manifest: homestead/capi/05-generate-cluster-manifest.sh"
echo "  3. Deploy cluster: homestead/capi/06-deploy-cluster.sh"
