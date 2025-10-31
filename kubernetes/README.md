# VM Static IP with Cilium LoadBalancer and BGP

This setup provides static IP addresses to VMs in a Kubernetes cluster using Cilium's native LoadBalancer capabilities with BGP advertisement.

## Overview

Instead of complex multi-network configurations, this approach uses Cilium LoadBalancer services to assign static IPs to VMs that:
- Persist across VM reboots
- Are advertised via BGP to upstream routers
- Provide direct connectivity without complex networking

## Architecture

```
VM (pod network: 10.100.x.x)
    ↓
LoadBalancer Service (static IP: 10.200.1.10)
    ↓
BGP Advertisement to Router (192.168.254.1)
    ↓
External Access via Static IP
```

## Components

### 1. LoadBalancer IP Pool
```yaml
# vm-loadbalancer-pool.yml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: vm-static-ips
spec:
  blocks:
  - cidr: "10.200.0.0/16"
```

### 2. LoadBalancer Service
```yaml
# vm-loadbalancer-service.yml
apiVersion: v1
kind: Service
metadata:
  name: test-vm-loadbalancer
  labels:
    bgp: "true"  # Required for BGP advertisement
  annotations:
    io.cilium/lb-ipam-ips: "10.200.1.10"  # Request specific IP
spec:
  type: LoadBalancer
  loadBalancerClass: io.cilium/bgp-control-plane
  selector:
    vm.kubevirt.io/name: test-vm  # Target the VM
  ports:
  - name: ssh
    port: 22
    targetPort: 22
    protocol: TCP
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
```

### 3. BGP Advertisement
```yaml
# loadbalancer-bgp-advertisement.yml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: loadbalancer-advertisement
  labels:
    advertise: "bgp"
spec:
  advertisements:
  - advertisementType: "Service"
    service:
      addresses:
      - "LoadBalancerIP"
    selector:
      matchLabels:
        bgp: "true"  # Only advertise services labeled with bgp=true
```

### 4. BGP Cluster Configuration
```yaml
# cilium-bgp-cluster-config.yml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux  # All Linux nodes
  bgpInstances:
  - name: "65005"
    localASN: 65005
    peers:
    - name: peer-65001
      peerAddress: 192.168.254.1
      peerASN: 65001
      peerConfigRef:
        name: peer-65001
```

## Key Requirements

1. **Service Labeling**: Services must be labeled with `bgp: "true"` to be advertised
2. **LoadBalancer Class**: Must use `io.cilium/bgp-control-plane`
3. **BGP Peering**: BGP peering must be established and working
4. **Service Selector**: BGP advertisement must have selector matching service labels

## Verification

Check BGP routes being advertised:
```bash
kubectl exec -n kube-system cilium-566wx -- cilium bgp routes advertised ipv4 unicast
```

Should show:
```
VRouter   Peer            Prefix           NextHop        Age     Attrs
65005     192.168.254.1   10.200.1.10/32   10.75.75.195   1m      [{Origin: i} {AsPath: 65005} {Nexthop: 10.75.75.195}]
```

Test connectivity:
```bash
ssh cirros@10.200.1.10  # Password: kubevirt
```

## Limitations

- **Port-specific**: LoadBalancer services only forward traffic to configured ports
- **No ICMP**: Ping may not work due to port limitations
- **Service overhead**: Each VM needs a dedicated LoadBalancer service

## All-Traffic Forwarding (Alternative)

For full traffic forwarding including ICMP ping, you would need different approaches:

1. **L2 Announcements**: Use Cilium L2 announcements instead of BGP
2. **ExternalIP**: Use ExternalIP on regular services with broader port ranges
3. **NodePort**: Use NodePort services with specific node scheduling

The LoadBalancer approach is ideal for specific service ports but doesn't support all traffic types.

---

# Cilium BGP Commands Reference

## Core BGP Status Commands

**Check BGP peer status:**
```bash
cilium bgp peers
# Shows: Local AS, Peer AS, Peer Address, Session status, Uptime, Family, Routes received/advertised
```

**General Cilium status with BGP info:**
```bash
cilium status --verbose
```

## BGP Route Commands

**Show routes advertised to peers:**
```bash
cilium bgp routes advertised ipv4 unicast
```

**Show routes received from peers:**
```bash
# Note: 'received' may not be available in all Cilium versions
# Use 'cilium bgp peers' to see received route counts instead
cilium bgp peers
```

**Show all available routes in BGP table:**
```bash
cilium bgp routes available ipv4 unicast
```

## Using cilium-dbg (Pod Execution)

When running from outside the cluster or if `cilium` command isn't available:

```bash
kubectl exec -it -n kube-system ds/cilium -- cilium-dbg bgp peers
kubectl exec -it -n kube-system ds/cilium -- cilium-dbg bgp routes advertised ipv4 unicast
kubectl exec -it -n kube-system ds/cilium -- cilium-dbg bgp routes available ipv4 unicast
# Note: 'received' command may not be available in all versions
```

## Kubernetes Resource Commands

**Check BGP configurations:**
```bash
kubectl get ciliumbgpclusterconfigs
kubectl get ciliumbgppeerconfigs
kubectl get ciliumbgpadvertisements
kubectl get ciliumbgpnodeconfigs
```

**Detailed view:**
```bash
kubectl describe ciliumbgpnodeconfigs
kubectl describe ciliumbgpclusterconfigs
kubectl describe ciliumbgppeerconfigs
```

## IPv6 Variants

Replace `ipv4` with `ipv6` for IPv6 routes:
```bash
cilium bgp routes advertised ipv6 unicast
cilium bgp routes available ipv6 unicast
# Note: 'received' may not be available - use 'cilium bgp peers' for route counts
```

## Common Troubleshooting Sequence

1. **Check peer connectivity:**
   ```bash
   cilium bgp peers
   ```

2. **Verify route advertisement:**
   ```bash
   cilium bgp routes advertised ipv4 unicast
   ```

3. **Check received routes (via peer status):**
   ```bash
   cilium bgp peers
   # Look at the "Received" column for route counts
   ```

4. **Review configuration status:**
   ```bash
   kubectl describe ciliumbgpnodeconfigs
   ```

---

# DNS Records for Kubernetes Clusters

## Current Clusters

### Cluster: kubevirt (vm-101.102.cofront.xyz)
- **Pod CIDR**: 10.100.0.0/20
- **Service CIDR**: 10.100.16.0/20
- **Control Plane**: vm-101.102.cofront.xyz

### Cluster: cnidev (vm-102.102.cofront.xyz)
- **Pod CIDR**: 10.101.0.0/20
- **Service CIDR**: 10.101.16.0/20
- **Control Plane**: vm-102.102.cofront.xyz

### Cluster: okd-1
- **Pod CIDR**: 10.102.0.0/20
- **Service CIDR**: 10.102.16.0/20
- **Control Plane Nodes**:
  - master-1.okd-1.cofront.xyz
  - master-2.okd-1.cofront.xyz
  - master-3.okd-1.cofront.xyz

## Route53 UI Paste Format

### For okd-1 cluster (3 masters):
```
master-1.okd-1.cofront.xyz    300    A    <MASTER-1-IP>
master-2.okd-1.cofront.xyz    300    A    <MASTER-2-IP>
master-3.okd-1.cofront.xyz    300    A    <MASTER-3-IP>
api.okd-1.cofront.xyz         300    A    <API-ENDPOINT-IP>
*.apps.okd-1.cofront.xyz      300    A    <INGRESS-IP>
```

**Notes:**
- `api.okd-1.cofront.xyz` - For HA, use load balancer IP; for single node, use master-1 IP
- `*.apps.okd-1.cofront.xyz` - Wildcard for ingress (optional but recommended)

### Generic template for new cluster:
```
master-1.<cluster>.cofront.xyz    300    A    <IP>
master-2.<cluster>.cofront.xyz    300    A    <IP>
master-3.<cluster>.cofront.xyz    300    A    <IP>
api.<cluster>.cofront.xyz         300    A    <IP>
*.apps.<cluster>.cofront.xyz      300    A    <IP>
```

## DNS Validation

```bash
dig +short master-1.okd-1.cofront.xyz
dig +short api.okd-1.cofront.xyz
dig +short test.apps.okd-1.cofront.xyz
```

## Using DNS with kubeadm

For HA clusters, specify the API endpoint:

```bash
sudo kubeadm init \
  --control-plane-endpoint "api.okd-1.cofront.xyz:6443" \
  --pod-network-cidr=10.102.0.0/20 \
  --service-cidr=10.102.16.0/20
```

---

# Multi-Node Control Plane Setup (HA)

## Overview

For a highly available Kubernetes cluster with multiple control plane nodes, you need to:
1. Initialize the first control plane node with special flags
2. Join additional control plane nodes using certificate sharing
3. Set up a load balancer for the API endpoint (optional but recommended)

## Prerequisites

- DNS records created for all master nodes and API endpoint
- Load balancer configured (HAProxy, nginx, cloud LB) pointing to all control plane nodes on port 6443
  - OR use round-robin DNS for `api.<cluster>.cofront.xyz`
- All nodes have:
  - Same container runtime (containerd/CRI-O)
  - Same Kubernetes version packages installed
  - Network connectivity between all nodes
  - Time synchronized (NTP)

## Step 1: Initialize First Control Plane Node

On **master-1** only:

```bash
sudo kubeadm init \
  --control-plane-endpoint "api.okd-1.cofront.xyz:6443" \
  --upload-certs \
  --pod-network-cidr=10.102.0.0/20 \
  --service-cidr=10.102.16.0/20 \
  --skip-phases=addon/kube-proxy
```

**Key flags:**
- `--control-plane-endpoint`: DNS name for the API endpoint (shared by all masters)
- `--upload-certs`: Uploads control plane certificates to a Kubernetes Secret for other masters to download
- `--skip-phases=addon/kube-proxy`: Skip kube-proxy if using Cilium/OVN-K for routing

**Save the output!** You'll see two join commands:
1. One for joining worker nodes
2. One for joining control plane nodes (includes `--control-plane` and `--certificate-key`)

## Step 2: Configure kubectl on master-1

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## Step 3: Install CNI Plugin

Install your CNI (Cilium, OVN-Kubernetes, etc.) on master-1 before joining other nodes.

```bash
# Example for Cilium
./install-cilium.sh
```

## Step 4: Join Additional Control Plane Nodes

On **master-2** and **master-3**, use the control plane join command from Step 1 output:

```bash
sudo kubeadm join api.okd-1.cofront.xyz:6443 \
  --token <token-from-init> \
  --discovery-token-ca-cert-hash sha256:<hash-from-init> \
  --control-plane \
  --certificate-key <cert-key-from-init>
```

**Note:** The certificate key expires after 2 hours. If you need to join a control plane node later, regenerate it:

```bash
# On master-1
sudo kubeadm init phase upload-certs --upload-certs
```

## Step 5: Configure kubectl on Additional Masters

On **master-2** and **master-3**:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## Step 6: Verify Cluster

```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl get componentstatuses
```

All control plane nodes should show as Ready.

## Load Balancer Configuration

### Option 1: HAProxy (Recommended)

On a separate VM or the first master before init:

```haproxy
# /etc/haproxy/haproxy.cfg
frontend kubernetes-api
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-api-backend

backend kubernetes-api-backend
    mode tcp
    balance roundrobin
    option tcp-check
    server master-1 master-1.okd-1.cofront.xyz:6443 check
    server master-2 master-2.okd-1.cofront.xyz:6443 check
    server master-3 master-3.okd-1.cofront.xyz:6443 check
```

### Option 2: Round-Robin DNS

Configure `api.okd-1.cofront.xyz` with multiple A records:
```
api.okd-1.cofront.xyz    300    A    <master-1-ip>
api.okd-1.cofront.xyz    300    A    <master-2-ip>
api.okd-1.cofront.xyz    300    A    <master-3-ip>
```

**Note:** Less reliable than a proper load balancer, but simpler for dev/test.

## Troubleshooting

### Certificate Key Expired
If you see "failed to download certificates" when joining:
```bash
# On master-1
sudo kubeadm init phase upload-certs --upload-certs
# Use the new certificate key in the join command
```

### API Endpoint Not Reachable
- Verify DNS resolution: `dig +short api.okd-1.cofront.xyz`
- Check firewall: port 6443 must be open between all nodes
- Test load balancer: `curl -k https://api.okd-1.cofront.xyz:6443/healthz`

### etcd Issues
View etcd cluster health:
```bash
kubectl exec -n kube-system etcd-master-1 -- etcdctl \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  member list
```

## References

- Current `install-via-kubeadm.sh` script handles single-node setup
- For HA setup, modify script to include `--control-plane-endpoint` and `--upload-certs`
- Create separate `join-control-plane.sh` script for master-2 and master-3