#!/bin/bash
set -euo pipefail

echo "=== Kubernetes Single-Node Installation with Flannel ==="

# Check if cluster is already initialized
if [ -f /etc/kubernetes/admin.conf ]; then
    echo "Cluster already initialized (admin.conf exists)"
    exit 0
fi

# Initialize cluster
# --pod-network-cidr required for Flannel (expects 10.244.0.0/16)
echo "Initializing cluster..."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Set up kubeconfig
echo "Setting up kubeconfig..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel CNI (latest version via GitHub releases)
echo "Installing Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Untaint control-plane node for single-node cluster
echo "Allowing workload scheduling on control-plane..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

echo ""
echo "=== Installation Complete ==="
kubectl get nodes
