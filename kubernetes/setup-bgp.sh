#!/bin/bash

set -e

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Please ensure cluster is initialized first."
    exit 1
fi

# Detect hostname and set BGP configuration
HOSTNAME=$(hostname -f)

if [[ "$HOSTNAME" == "vm-101.102.cofront.xyz" ]]; then
    POD_NETWORK_CIDR="10.100.0.0/20"
elif [[ "$HOSTNAME" == "vm-102.102.cofront.xyz" ]]; then
    POD_NETWORK_CIDR="10.101.0.0/20"
else
    echo "Unknown hostname: $HOSTNAME"
    echo "Expected vm-101.102.cofront.xyz or vm-102.102.cofront.xyz"
    exit 1
fi

# Get local IP address for BGP router ID
BGP_ROUTER_ID=$(hostname -I | awk '{print $1}')

# BGP configuration
LOCAL_ASN="65006"
PEER_IP="192.168.254.1"
PEER_ASN="65001"

echo "Setting up BGP on $HOSTNAME"
echo "Pod network CIDR: $POD_NETWORK_CIDR"
echo "Local ASN: $LOCAL_ASN"
echo "BGP Router ID: $BGP_ROUTER_ID"
echo "Peer IP: $PEER_IP (multi-hop)"
echo "Peer ASN: $PEER_ASN"
echo ""

# Check if OVN-Kubernetes is installed
if ! kubectl get pods -n kube-system -l app=ovnkube-node &> /dev/null; then
    echo "ERROR: OVN-Kubernetes is not installed. Please run install-ovn-kubernetes.sh first."
    exit 1
fi

echo ""
echo "Installing FRR-K8S..."

# Install FRR-K8S (MetalLB's FRR Kubernetes integration)
kubectl apply -f https://raw.githubusercontent.com/metallb/frr-k8s/main/config/all-in-one/frr-k8s.yaml

echo "Waiting for FRR-K8S daemon to be ready..."
sleep 10
kubectl get pods -n frr-k8s-system

echo ""
echo "Creating FRR Configuration for BGP peering..."

# Create FRRConfiguration
kubectl apply -f - <<EOF
apiVersion: frrk8s.metallb.io/v1beta1
kind: FRRConfiguration
metadata:
  name: bgp-config
  namespace: frr-k8s-system
spec:
  bgp:
    routers:
    - asn: ${LOCAL_ASN}
      id: ${BGP_ROUTER_ID}
      neighbors:
      - asn: ${PEER_ASN}
        address: ${PEER_IP}
        port: 179
        ebgpMultiHop: true
EOF

echo ""
echo "Creating RouteAdvertisements to advertise pod network..."

# Create RouteAdvertisements CR
kubectl apply -f - <<EOF
apiVersion: k8s.ovn.org/v1
kind: RouteAdvertisements
metadata:
  name: advertise-pod-network
spec:
  advertisements:
  - podNetwork: true
    targetVRF: ""
EOF

echo ""
echo "BGP setup complete!"
echo ""
echo "Verifying configuration..."
kubectl get frrconfigurations -n frr-k8s-system
kubectl get routeadvertisements
echo ""
echo "Configuration summary:"
echo "  Local ASN: ${LOCAL_ASN}"
echo "  BGP Router ID: ${BGP_ROUTER_ID}"
echo "  Peer IP: ${PEER_IP}"
echo "  Peer ASN: ${PEER_ASN}"
echo "  Advertising: ${POD_NETWORK_CIDR}"
echo ""
echo "To check BGP status:"
echo "  kubectl logs -n frr-k8s-system -l app=frr-k8s -c frr"
echo "  kubectl exec -n frr-k8s-system -l app=frr-k8s -c frr -- vtysh -c 'show bgp summary'"
