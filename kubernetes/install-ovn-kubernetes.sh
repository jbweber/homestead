#!/bin/bash

set -e

# Check if required tools are available
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Please ensure cluster is initialized first."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "helm not found. Please install helm first."
    exit 1
fi

# Detect hostname and set network configuration to match kubeadm setup
HOSTNAME=$(hostname -f)

if [[ "$HOSTNAME" == "vm-101.102.cofront.xyz" ]]; then
    POD_NETWORK_CIDR="10.100.0.0/20"
    SERVICE_CIDR="10.100.16.0/20"
elif [[ "$HOSTNAME" == "vm-102.102.cofront.xyz" ]]; then
    POD_NETWORK_CIDR="10.101.0.0/20"
    SERVICE_CIDR="10.101.16.0/20"
else
    echo "Unknown hostname: $HOSTNAME"
    echo "Expected vm-101.102.cofront.xyz or vm-102.102.cofront.xyz"
    exit 1
fi

echo "Installing OVN-Kubernetes on $HOSTNAME"
echo "Pod network CIDR: $POD_NETWORK_CIDR"
echo "Service CIDR: $SERVICE_CIDR"

# Check if already installed
if helm status ovn-kubernetes -n kube-system &> /dev/null; then
    echo "OVN-Kubernetes is already installed"
    exit 0
fi

# Clone ovn-kubernetes repository if not exists
if [ ! -d "ovn-kubernetes" ]; then
    echo "Cloning ovn-kubernetes repository..."
    git clone https://github.com/ovn-org/ovn-kubernetes.git
fi

cd ovn-kubernetes/helm/ovn-kubernetes

# Get k8s API server address
K8S_API_SERVER="https://$(kubectl get pods --all-namespaces -l component=kube-apiserver -o jsonpath='{.items[0].status.hostIP}'):6443"

# Create values file for BGP mode
cat > /tmp/ovn-kubernetes-values.yaml <<EOF
global:

  # Network CIDRs
  netCidr: ${POD_NETWORK_CIDR}
  svcCidr: ${SERVICE_CIDR}

  # Enable BGP mode
  enableMultiExternalGateway: true

  # Enable route advertisements feature for BGP
  enableRouteAdvertisements: true

  # Disable features not needed
  enableInterconnect: false
  enableHybridOverlay: false

  # Use smart-nic-host mode - doesn't manage host networking
  ovnKubeNodeMode: smart-nic-host
EOF

echo "Installing OVN-Kubernetes with Helm..."
helm install ovn-kubernetes . \
    -f values-no-ic.yaml \
    -f /tmp/ovn-kubernetes-values.yaml \
    --set k8sAPIServer=https://10.100.102.102:6443

echo ""
echo "OVN-Kubernetes installation complete."
echo "To check status, run:"
echo "  kubectl get pods -n kube-system -l app=ovnkube-node"
echo "  helm status ovn-kubernetes -n kube-system"
echo ""
echo "Note: Using smart-nic-host mode - OVN won't manage host network interface."
echo "Multi-external-gateway enabled for BGP routing."
