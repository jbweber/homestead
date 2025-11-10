#!/bin/bash
set -euo pipefail

echo "=== Installing Metal3 Infrastructure Provider ==="

# Check if clusterctl is installed
if ! command -v clusterctl &> /dev/null; then
    echo "Error: clusterctl is not installed"
    echo "Run: homestead/capi/01-install-clusterctl.sh"
    exit 1
fi

# Version to install
CAPM3_VERSION="v1.11.1"

echo "Target version: $CAPM3_VERSION"
echo ""

# Check if CAPM3 is already installed
if kubectl get namespace capm3-system &> /dev/null; then
    echo "Metal3 infrastructure provider is already installed"
    echo ""
    echo "Current providers:"
    kubectl get providers -A
    echo ""
    echo "To reinstall, delete the existing installation:"
    echo "  clusterctl delete --infrastructure metal3"
    exit 0
fi

# Verify prerequisites
echo "Verifying prerequisites..."

# Check if CAPI core is installed
if ! kubectl get namespace capi-system &> /dev/null; then
    echo "Error: Cluster API core is not installed"
    echo "Run: homestead/capi/02-install-capi-core.sh"
    exit 1
fi

# Verify CAPI core is ready
if ! kubectl wait --for=condition=Available --timeout=60s \
    deployment/capi-controller-manager -n capi-system &> /dev/null; then
    echo "Error: CAPI core controller is not ready"
    exit 1
fi

# Check if BMO (Bare Metal Operator) is installed
if ! kubectl get namespace baremetal-operator-system &> /dev/null; then
    echo "Warning: Bare Metal Operator namespace not found"
    echo "BMO should be installed via homestead/metal3/05-install-bmo.sh"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "✓ Cluster API core installed and ready"
echo ""

# Install CAPM3 infrastructure provider and IPAM provider
echo "Installing Metal3 infrastructure provider and IPAM provider..."
echo "This may take a few minutes..."
echo ""

clusterctl init --infrastructure metal3:${CAPM3_VERSION} --ipam metal3

echo ""
echo "Waiting for CAPM3 components to be ready..."

# Wait for CAPM3 controller
kubectl wait --for=condition=Available --timeout=300s \
    deployment/capm3-controller-manager -n capm3-system

echo ""
echo "Waiting for Metal3 IPAM controller to be ready..."

# Wait for IPAM controller
kubectl wait --for=condition=Available --timeout=300s \
    deployment/ipam-controller-manager -n metal3-ipam-system

echo ""
echo "=== Installation Complete ==="
echo ""

# Display all installed providers
echo "Installed providers:"
clusterctl get providers

echo ""
echo "CAPM3 deployment status:"
kubectl get deployment -n capm3-system

echo ""
echo "Metal3 IPAM deployment status:"
kubectl get deployment -n metal3-ipam-system

echo ""
echo "Integration check:"
echo "BareMetalHost CRD:"
kubectl get crd baremetalhosts.metal3.io -o custom-columns=NAME:.metadata.name,VERSION:.spec.versions[0].name
echo "IPPool CRD:"
kubectl get crd ippools.ipam.metal3.io -o custom-columns=NAME:.metadata.name,VERSION:.spec.versions[0].name

echo ""
echo "Next steps:"
echo "  Run: homestead/capi/04-verify-installation.sh"
