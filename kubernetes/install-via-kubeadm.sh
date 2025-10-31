#!/bin/bash

# Check if cluster is already initialized
if [ -f /etc/kubernetes/admin.conf ]; then
    echo "Cluster already initialized on this node (admin.conf exists)"
    exit 0
fi

# Detect hostname and set network configuration
HOSTNAME=$(hostname -f)

if [[ "$HOSTNAME" == "vm-101.102.cofront.xyz" ]]; then
    POD_NETWORK_CIDR="10.100.0.0/20"
    SERVICE_CIDR="10.100.16.0/20"
elif [[ "$HOSTNAME" == "vm-102.102.cofront.xyz" ]]; then
    POD_NETWORK_CIDR="10.101.0.0/20"
    SERVICE_CIDR="10.101.16.0/20"
elif [[ "$HOSTNAME" == "master-1.okd-1.cofront.xyz" ]]; then
    POD_NETWORK_CIDR="10.102.0.0/20"
    SERVICE_CIDR="10.102.16.0/20"
else
    echo "Unknown hostname: $HOSTNAME"
    echo "Expected vm-101.102.cofront.xyz, vm-102.102.cofront.xyz, or master-1.okd-1.cofront.xyz"
    exit 1
fi

echo "Initializing cluster on $HOSTNAME"
echo "Pod network CIDR: $POD_NETWORK_CIDR"
echo "Service CIDR: $SERVICE_CIDR"

sudo kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR --service-cidr=$SERVICE_CIDR --skip-phases=addon/kube-proxy > kubeadm-$(date +%s).log 2>&1

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
