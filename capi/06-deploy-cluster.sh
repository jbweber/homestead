#!/bin/bash
set -euo pipefail

echo "=== Deploying Cluster ==="
echo ""

# Require manifest file path as argument
if [ $# -ne 1 ]; then
    echo "Error: Missing required argument"
    echo ""
    echo "Usage: $0 <path/to/cluster-manifest.yaml>"
    echo ""
    echo "Example:"
    echo "  $0 ~/projects/environment-files/super-single-node/super-manifest.yaml"
    echo ""
    exit 1
fi

MANIFEST_FILE="$1"

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Error: Cluster manifest not found: $MANIFEST_FILE"
    echo ""
    echo "Generate the manifest first using script 05"
    exit 1
fi

# Extract cluster name and namespace from manifest
CLUSTER_NAME=$(grep -A5 "^kind: Cluster$" "$MANIFEST_FILE" | grep "  name:" | head -1 | awk '{print $2}')
NAMESPACE=$(grep -A5 "^kind: Cluster$" "$MANIFEST_FILE" | grep "  namespace:" | head -1 | awk '{print $2}')

if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: Could not extract cluster name from manifest"
    exit 1
fi

if [ -z "$NAMESPACE" ]; then
    NAMESPACE="default"
fi

echo "Cluster: $CLUSTER_NAME"
echo "Manifest: $MANIFEST_FILE"
echo ""

# Check if cluster already exists
if kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "Warning: Cluster '$CLUSTER_NAME' already exists"
    echo ""
    kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE"
    echo ""
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        kubectl delete cluster "$CLUSTER_NAME" -n "$NAMESPACE"
        echo "Waiting for cluster to be fully deleted..."
        kubectl wait --for=delete cluster/"$CLUSTER_NAME" -n "$NAMESPACE" --timeout=300s || true
    else
        echo "Aborting deployment"
        exit 0
    fi
fi

# Apply the manifest
echo "Applying cluster manifest..."
kubectl apply -f "$MANIFEST_FILE"

echo ""
echo "Cluster resources created. Monitoring deployment..."
echo ""

# Wait for cluster to be created
echo "Waiting for Cluster resource to be ready..."
if ! kubectl wait --for=condition=Ready cluster/"$CLUSTER_NAME" -n "$NAMESPACE" --timeout=1800s; then
    echo ""
    echo "Warning: Cluster did not become ready within 30 minutes"
    echo "This is normal for bare metal provisioning, which can take time"
    echo ""
fi

# Monitor control plane
echo ""
echo "Monitoring control plane initialization..."
CONTROL_PLANE_NAME="${CLUSTER_NAME}"

if kubectl get kubeadmcontrolplane "$CONTROL_PLANE_NAME" -n "$NAMESPACE" &> /dev/null; then
    kubectl wait --for=condition=Ready kubeadmcontrolplane/"$CONTROL_PLANE_NAME" -n "$NAMESPACE" --timeout=1800s || true
fi

echo ""
echo "=== Cluster Status ==="
echo ""

# Show cluster status
kubectl get cluster -n "$NAMESPACE"
echo ""

# Show machines
echo "Machines:"
kubectl get machines -n "$NAMESPACE"
echo ""

# Show control plane
echo "Control Plane:"
kubectl get kubeadmcontrolplane -n "$NAMESPACE" || echo "No KubeadmControlPlane found"
echo ""

# Show BareMetalHosts
echo "BareMetalHosts:"
kubectl get baremetalhosts -A
echo ""

# Retrieve kubeconfig if cluster is ready
# Save it in the same directory as the manifest
MANIFEST_DIR="$(dirname "$MANIFEST_FILE")"
KUBECONFIG_FILE="${MANIFEST_DIR}/${CLUSTER_NAME}-kubeconfig.yaml"

if kubectl get secret "${CLUSTER_NAME}-kubeconfig" -n "$NAMESPACE" &> /dev/null; then
    echo "Retrieving cluster kubeconfig..."
    clusterctl get kubeconfig "$CLUSTER_NAME" -n "$NAMESPACE" > "$KUBECONFIG_FILE"

    if [ -f "$KUBECONFIG_FILE" ]; then
        echo "✓ Kubeconfig saved to: $KUBECONFIG_FILE"
        echo ""
        echo "Access the new cluster with:"
        echo "  export KUBECONFIG=$KUBECONFIG_FILE"
        echo "  kubectl get nodes"
        echo ""

        # Try to check cluster health
        echo "Checking new cluster health..."
        if KUBECONFIG="$KUBECONFIG_FILE" kubectl get nodes &> /dev/null; then
            echo ""
            echo "Cluster nodes:"
            KUBECONFIG="$KUBECONFIG_FILE" kubectl get nodes
            echo ""
            echo "Cluster pods:"
            KUBECONFIG="$KUBECONFIG_FILE" kubectl get pods -A
        else
            echo "Cluster API server not yet accessible"
            echo "This is normal during initial provisioning"
        fi
    fi
else
    echo "Kubeconfig secret not yet available"
    echo "Retrieve it later with:"
    echo "  clusterctl get kubeconfig $CLUSTER_NAME -n $NAMESPACE > $KUBECONFIG_FILE"
fi

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Monitor cluster progress:"
echo "  kubectl get cluster -n $NAMESPACE -w"
echo "  kubectl get machines -n $NAMESPACE -w"
echo "  kubectl get baremetalhosts -A -w"
