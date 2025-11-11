#!/bin/bash
# Generate Cilium CNI manifests for CAPI/Metal3 clusters
# Usage: ./generate-cilium-manifests.sh <output-directory>
#
# This script generates rendered Cilium manifests that can be deployed
# via ClusterResourceSet for automated CNI installation on new clusters.
#
# Arguments:
#   output-directory: Directory where cilium-manifests.yaml will be created
#
# Example:
#   ./generate-cilium-manifests.sh /home/jweber/projects/environment-files/capi-1/cilium

set -euo pipefail

CILIUM_VERSION="1.18.3"  # Use stable version (1.18.2 in kubernetes/install-cilium.sh, but 1.18.3 is latest stable)

# Check for required arguments
if [ $# -lt 2 ]; then
    echo "Error: Output directory and API server host arguments required"
    echo ""
    echo "Usage: $0 <output-directory> <api-server-host> [api-server-port]"
    echo ""
    echo "Arguments:"
    echo "  output-directory  - Directory where manifests will be generated"
    echo "  api-server-host   - Kubernetes API server IP or hostname (e.g., 10.250.250.29)"
    echo "  api-server-port   - Kubernetes API server port (default: 6443)"
    echo ""
    echo "Examples:"
    echo "  $0 /home/jweber/projects/environment-files/capi-1/cilium 10.250.250.29"
    echo "  $0 /home/jweber/projects/environment-files/capi-1/cilium 10.250.250.29 6443"
    exit 1
fi

OUTPUT_DIR="$1"
K8S_API_HOST="$2"
K8S_API_PORT="${3:-6443}"

# Ensure helm is installed
if ! command -v helm &> /dev/null; then
    echo "Error: helm not found in PATH"
    echo "Install helm first: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Generating Cilium ${CILIUM_VERSION} manifests..."
echo "Output directory: ${OUTPUT_DIR}"
echo ""
echo "Configuration Options (from kubernetes/install-cilium.sh):"
echo ""
echo "  --version ${CILIUM_VERSION}"
echo "    Cilium version to install"
echo ""
echo "  --set k8sServiceHost=${K8S_API_HOST}"
echo "  --set k8sServicePort=${K8S_API_PORT}"
echo "    Kubernetes API server endpoint for Cilium to connect to"
echo "    - CRITICAL: Required when using kubeProxyReplacement=true"
echo "    - Init containers use this to contact the API server during bootstrap"
echo "    - Without these, Cilium tries to use Service ClusterIP (10.96.0.1:443)"
echo "    - Service ClusterIP won't work until Cilium itself is running (chicken-egg)"
echo "    - Should be set to the control plane VIP IP address (e.g., kube-vip)"
echo "    - Use IP address instead of DNS name to avoid DNS bootstrap dependency"
echo ""
echo "  --set kubeProxyReplacement=true"
echo "    Replace kube-proxy with Cilium's eBPF implementation"
echo "    - More efficient than iptables-based kube-proxy"
echo "    - Better performance for service load balancing"
echo "    - Enables advanced features like DSR (Direct Server Return)"
echo ""
echo "  --set bgpControlPlane.enabled=true"
echo "    Enable BGP control plane for LoadBalancer IP advertisement"
echo "    - Allows advertising LoadBalancer IPs to upstream routers"
echo "    - Essential for bare metal LoadBalancer services"
echo "    - Note: This only enables the subsystem; BGP peering configured separately"
echo ""
echo "  --set ipam.mode=kubernetes"
echo "    Use Kubernetes' built-in IPAM for pod IP allocation"
echo "    - Leverages node.spec.podCIDR from Kubernetes"
echo "    - No external IPAM service required"
echo "    - Standard Kubernetes networking model"
echo ""
echo "  --set cni.binPath=/var/lib/cni/bin"
echo "    CNI plugin binary path for custom Fedora images"
echo "    - Custom Fedora image uses /var/lib/cni/bin (writable in bootc)"
echo "    - /opt/cni/bin is a symlink for compatibility"
echo "    - See fedora-kiwi-descriptions/README-CUSTOM.md for details"
echo ""
echo "  --set cni.exclusive=true"
echo "    Cilium manages the CNI configuration exclusively"
echo "    - Prevents conflicts with other CNI plugins"
echo "    - Ensures Cilium is the only active CNI"
echo "    - Recommended for production clusters"
echo ""
echo "  --set routingMode=native"
echo "    Use native routing without tunnels (VXLAN/Geneve)"
echo "    - Better performance on bare metal"
echo "    - Lower CPU overhead (no encapsulation)"
echo "    - Requires IP routing between nodes"
echo "    - Equivalent to tunnel=disabled"
echo ""
echo "  --set autoDirectNodeRoutes=true"
echo "    Automatically configure direct routes between nodes"
echo "    - Cilium installs routes for pod CIDRs on each node"
echo "    - Works with native routing mode"
echo "    - No manual route configuration needed"
echo ""
echo "  --set enableIPv4Masquerade=false"
echo "    Disable SNAT masquerading for pod traffic"
echo "    - Pods use their real IPs when talking to external services"
echo "    - Requires network infrastructure to route pod CIDRs"
echo "    - Better for debugging and traceability"
echo "    - Set to true if pods can't reach external networks"
echo ""
echo "  --set socketLB.hostNamespaceOnly=true"
echo "    Restrict socket-level load balancing to host namespace"
echo "    - More conservative security posture"
echo "    - Prevents socket LB from affecting all pods"
echo "    - Recommended for multi-tenant clusters"
echo ""

# Add Cilium Helm repository
echo "Adding Cilium Helm repository..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium

# Generate full Kubernetes manifests using Helm template
echo "Generating manifests..."
helm template cilium cilium/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --set k8sServiceHost="${K8S_API_HOST}" \
  --set k8sServicePort="${K8S_API_PORT}" \
  --set kubeProxyReplacement=true \
  --set bgpControlPlane.enabled=true \
  --set ipam.mode=kubernetes \
  --set cni.binPath=/var/lib/cni/bin \
  --set cni.exclusive=true \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set enableIPv4Masquerade=false \
  --set socketLB.hostNamespaceOnly=true \
  > "${OUTPUT_DIR}/cilium-manifests.yaml"

echo ""
echo "✓ Generated Kubernetes manifests: ${OUTPUT_DIR}/cilium-manifests.yaml"
echo "  Size: $(wc -l < "${OUTPUT_DIR}/cilium-manifests.yaml") lines"
echo ""
echo "Next steps:"
echo "  1. Review the generated manifest file"
echo "  2. Create ConfigMap for ClusterResourceSet"
echo "  3. Create ClusterResourceSet definition"
echo "  4. Apply to management cluster"
