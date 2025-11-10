#!/bin/bash
set -euo pipefail

echo "=== Generating Cluster Manifest ==="
echo ""

# Check if clusterctl is installed
if ! command -v clusterctl &> /dev/null; then
    echo "Error: clusterctl is not installed"
    echo "Run: homestead/capi/01-install-clusterctl.sh"
    exit 1
fi

# Environment variables file and output path
# Require both as arguments
if [ $# -ne 2 ]; then
    echo "Error: Missing required arguments"
    echo ""
    echo "Usage: $0 <path/to/cluster-variables.rc> <output-manifest.yaml>"
    echo ""
    echo "Example:"
    echo "  $0 ~/projects/environment-files/super-single-node/cluster-variables.rc \\"
    echo "     ~/projects/environment-files/super-manifest.yaml"
    echo ""
    echo "See: homestead/capi/README.md for required variables"
    exit 1
fi

ENV_FILE="$1"
OUTPUT_FILE="$2"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment variables file not found: $ENV_FILE"
    echo ""
    echo "Create this file with cluster configuration variables."
    echo "See: homestead/capi/README.md for required variables"
    exit 1
fi

# Ensure output directory exists
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Error: Output directory does not exist: $OUTPUT_DIR"
    exit 1
fi

# Source environment variables
echo "Loading environment variables from: $ENV_FILE"
source "$ENV_FILE"
echo ""

# Validate required variables
REQUIRED_VARS=(
    "CLUSTER_NAME"
    "KUBERNETES_VERSION"
    "POD_CIDR"
    "SERVICE_CIDR"
    "API_ENDPOINT_HOST"
    "API_ENDPOINT_PORT"
    "CONTROL_PLANE_MACHINE_COUNT"
    "WORKER_MACHINE_COUNT"
    "IMAGE_URL"
    "IMAGE_CHECKSUM"
    "IMAGE_CHECKSUM_TYPE"
    "IMAGE_FORMAT"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "Error: Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Update: $ENV_FILE"
    exit 1
fi

echo "Cluster configuration:"
echo "  Name: $CLUSTER_NAME"
echo "  Kubernetes version: $KUBERNETES_VERSION"
echo "  Control plane nodes: $CONTROL_PLANE_MACHINE_COUNT"
echo "  Worker nodes: $WORKER_MACHINE_COUNT"
echo "  API endpoint: $API_ENDPOINT_HOST:$API_ENDPOINT_PORT"
echo "  Pod CIDR: $POD_CIDR"
echo "  Service CIDR: $SERVICE_CIDR"
echo ""

# Generate cluster manifest using clusterctl
echo "Generating cluster manifest..."
echo "This uses the Metal3 provider template..."
echo ""

# Use clusterctl generate cluster command
# The template comes from the CAPM3 provider
clusterctl generate cluster "$CLUSTER_NAME" \
    --infrastructure metal3 \
    --kubernetes-version "$KUBERNETES_VERSION" \
    --control-plane-machine-count "$CONTROL_PLANE_MACHINE_COUNT" \
    --worker-machine-count "$WORKER_MACHINE_COUNT" \
    > "$OUTPUT_FILE"

if [ $? -ne 0 ]; then
    echo "Error: Failed to generate cluster manifest"
    echo ""
    echo "Check that:"
    echo "  1. CAPM3 provider is installed (run 03-install-metal3-provider.sh)"
    echo "  2. All required environment variables are set"
    echo "  3. clusterctl can access the Metal3 template"
    exit 1
fi

echo "✓ Cluster manifest generated successfully"
echo ""
echo "Output file: $OUTPUT_FILE"
echo "File size: $(wc -c < "$OUTPUT_FILE") bytes"
echo ""

# Show a preview of the manifest
echo "=== Manifest Preview ==="
echo ""
echo "Resources to be created:"
kubectl apply --dry-run=client -f "$OUTPUT_FILE" 2>&1 | grep "created (dry run)" || echo "Unable to preview (kubectl might not support this version)"
echo ""

# Count resources
RESOURCE_COUNT=$(grep -c "^kind:" "$OUTPUT_FILE" || echo "0")
echo "Total resources in manifest: $RESOURCE_COUNT"
echo ""

# Show resource types
echo "Resource types:"
grep "^kind:" "$OUTPUT_FILE" | sort | uniq -c || echo "Unable to list resources"
echo ""

echo "=== Generation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Review the manifest: cat $OUTPUT_FILE"
echo "  2. Verify BareMetalHosts are available: kubectl get baremetalhosts -A"
echo "  3. Deploy the cluster: homestead/capi/06-deploy-cluster.sh"
