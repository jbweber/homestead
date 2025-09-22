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