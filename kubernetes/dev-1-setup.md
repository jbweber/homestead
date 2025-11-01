# dev-1 Kubernetes Cluster Setup Guide

## Cluster Information

- **Cluster Name:** dev-1.cofront.xyz
- **Pod CIDR:** 10.103.0.0/20
- **Service CIDR:** 10.103.16.0/20
- **Control Plane Endpoint:** api.dev-1.cofront.xyz:6443

## Node Configuration

| Node | FQDN | IP Address | Resources |
|------|------|------------|-----------|
| master-1 | master-1.dev-1.cofront.xyz | 10.254.254.101 | 32GB RAM, 8 vCPUs, 120GB disk |
| master-2 | master-2.dev-1.cofront.xyz | 10.254.254.102 | 32GB RAM, 8 vCPUs, 120GB disk |
| master-3 | master-3.dev-1.cofront.xyz | 10.254.254.103 | 32GB RAM, 8 vCPUs, 120GB disk |

---

## Step 1: Create DNS Records

Create these records in Route53 for cofront.xyz:

```
# Individual master nodes
master-1.dev-1.cofront.xyz    300    A    10.254.254.101
master-2.dev-1.cofront.xyz    300    A    10.254.254.102
master-3.dev-1.cofront.xyz    300    A    10.254.254.103

# API endpoint (round-robin DNS for HA)
api.dev-1.cofront.xyz         300    A    10.254.254.101
api.dev-1.cofront.xyz         300    A    10.254.254.102
api.dev-1.cofront.xyz         300    A    10.254.254.103

# Wildcard for ingress (optional but recommended)
*.apps.dev-1.cofront.xyz      300    A    10.254.254.101
```

### Verify DNS Resolution

```bash
# Test individual nodes
dig +short master-1.dev-1.cofront.xyz
dig +short master-2.dev-1.cofront.xyz
dig +short master-3.dev-1.cofront.xyz

# Test API endpoint (should return all 3 IPs)
dig +short api.dev-1.cofront.xyz

# Test wildcard
dig +short test.apps.dev-1.cofront.xyz
```

---

## Step 2: Initialize First Control Plane Node (master-1)

**On master-1.dev-1.cofront.xyz:**

```bash
# Initialize cluster with HA configuration
sudo kubeadm init \
  --control-plane-endpoint "api.dev-1.cofront.xyz:6443" \
  --upload-certs \
  --pod-network-cidr=10.103.0.0/20 \
  --service-cidr=10.103.16.0/20 \
  --skip-phases=addon/kube-proxy

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Allow pods to run on control plane (optional for testing)
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
```

**IMPORTANT:** Save the output from `kubeadm init`! You'll need:
- The join command for control plane nodes (includes `--control-plane` and `--certificate-key`)
- The join command for worker nodes (if you add workers later)

---

## Step 3: Install CNI Plugin (Choose One)

### Option A: Cilium (Recommended for BGP support)

```bash
# Download Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# Install Cilium
cilium install --version 1.16.3

# Wait for Cilium to be ready
cilium status --wait
```

### Option B: OVN-Kubernetes

See [install-ovn-kubernetes.sh](./install-ovn-kubernetes.sh) for reference.

---

## Step 4: Join Additional Control Plane Nodes

**On master-2.dev-1.cofront.xyz:**

Use the control plane join command from Step 2 output:

```bash
sudo kubeadm join api.dev-1.cofront.xyz:6443 \
  --token <TOKEN-FROM-INIT> \
  --discovery-token-ca-cert-hash sha256:<HASH-FROM-INIT> \
  --control-plane \
  --certificate-key <CERT-KEY-FROM-INIT>

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**On master-3.dev-1.cofront.xyz:**

Repeat the same join command as master-2.

**Note:** The certificate key expires after 2 hours. If expired, regenerate it on master-1:

```bash
# On master-1
sudo kubeadm init phase upload-certs --upload-certs
# Use the new certificate key in the join command
```

---

## Step 5: Verify Cluster

**From any master node:**

```bash
# Check all nodes are Ready
kubectl get nodes

# Expected output:
# NAME                           STATUS   ROLES           AGE   VERSION
# master-1.dev-1.cofront.xyz     Ready    control-plane   10m   v1.xx.x
# master-2.dev-1.cofront.xyz     Ready    control-plane   5m    v1.xx.x
# master-3.dev-1.cofront.xyz     Ready    control-plane   5m    v1.xx.x

# Check all system pods are running
kubectl get pods -n kube-system

# Verify etcd cluster health
kubectl get pods -n kube-system | grep etcd

# Should see 3 etcd pods (one per master)
```

---

## Step 6: Configure BGP (If using Cilium)

### Create BGP Peer Configuration

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: peer-65001
spec:
  authSecretRef: null
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 120
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"
EOF
```

### Create BGP Cluster Configuration

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
  - name: "65010"
    localASN: 65010
    peers:
    - name: peer-65001
      peerAddress: 192.168.254.1
      peerASN: 65001
      peerConfigRef:
        name: peer-65001
EOF
```

### Create BGP Advertisement

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
  labels:
    advertise: "bgp"
spec:
  advertisements:
    - advertisementType: "PodCIDR"
    - advertisementType: "Service"
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchLabels:
          bgp: "true"
EOF
```

**Note:** Adjust `peerAddress` and ASNs based on your BGP router configuration.

---

## Step 7: Verify BGP Peering (If configured)

```bash
# Check BGP peer status from Cilium
kubectl exec -it -n kube-system ds/cilium -- cilium-dbg bgp peers

# Expected output should show "established" session state

# Check advertised routes
kubectl exec -it -n kube-system ds/cilium -- cilium-dbg bgp routes advertised ipv4 unicast

# Verify BGP configurations
kubectl get ciliumbgpclusterconfigs
kubectl get ciliumbgppeerconfigs
kubectl get ciliumbgpadvertisements
```

---

## Step 8: Test Cluster

### Deploy a test application

```bash
# Create a simple nginx deployment
kubectl create deployment nginx --image=nginx

# Expose it
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Check the service
kubectl get svc nginx

# If using Cilium with LoadBalancer, you should get an external IP
```

### Test DNS resolution within cluster

```bash
# Run a test pod
kubectl run -it --rm debug --image=busybox --restart=Never -- sh

# Inside the pod, test DNS
nslookup kubernetes.default
exit
```

---

## Verification Checklist

- [ ] All 3 DNS records resolve correctly for master nodes
- [ ] api.dev-1.cofront.xyz returns all 3 IPs (round-robin)
- [ ] All 3 nodes show as "Ready" in `kubectl get nodes`
- [ ] All nodes have the "control-plane" role
- [ ] All kube-system pods are Running
- [ ] 3 etcd pods are running (one per master)
- [ ] CNI is installed and healthy
- [ ] BGP peering is established (if configured)
- [ ] Test deployment can be created and accessed

---

## Troubleshooting

### DNS not resolving
```bash
# Force DNS cache clear
sudo systemd-resolve --flush-caches
# Or wait for TTL (300 seconds)
```

### Certificate key expired when joining
```bash
# On master-1
sudo kubeadm init phase upload-certs --upload-certs
```

### Node not joining
```bash
# Check firewall (ports 6443, 2379-2380, 10250-10252)
# Check time synchronization
timedatectl status

# Reset and try again
sudo kubeadm reset
```

### API endpoint not reachable
```bash
# Test connectivity
curl -k https://api.dev-1.cofront.xyz:6443/healthz

# Check from each master
ping master-1.dev-1.cofront.xyz
ping master-2.dev-1.cofront.xyz
ping master-3.dev-1.cofront.xyz
```

---

## Network Allocation Summary

| Cluster | Pod CIDR | Service CIDR | Local ASN |
|---------|----------|--------------|-----------|
| kubevirt | 10.100.0.0/20 | 10.100.16.0/20 | 65005 |
| cnidev | 10.101.0.0/20 | 10.101.16.0/20 | 65006 |
| okd-1 | 10.102.0.0/20 | 10.102.16.0/20 | 65007 |
| **dev-1** | **10.103.0.0/20** | **10.103.16.0/20** | **65010** |

---

## Next Steps

After cluster is up and verified:

1. Install additional components (KubeVirt, monitoring, etc.)
2. Configure LoadBalancer IP pools if needed
3. Set up ingress controller
4. Configure persistent storage
5. Set up backup/restore procedures

---

## Quick Reference Commands

```bash
# View cluster info
kubectl cluster-info

# Check component health
kubectl get componentstatuses

# View all resources
kubectl get all -A

# Get node details
kubectl describe node master-1.dev-1.cofront.xyz

# View logs from a pod
kubectl logs -n kube-system <pod-name>

# Access etcd
sudo crictl ps | grep etcd
kubectl exec -n kube-system etcd-master-1.dev-1.cofront.xyz -- etcdctl member list
```
