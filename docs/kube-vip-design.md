# kube-vip and Cilium BGP Integration Design

## Overview

This document outlines the architecture for using kube-vip in BGP mode for control plane high availability alongside Cilium BGP for pod networking and service load balancing.

## Architecture Summary

### Component Responsibilities

**kube-vip (Control Plane VIP)**
- Provides highly available virtual IP for Kubernetes API server
- Runs as static pod on control plane nodes
- Uses BGP to advertise control plane VIP
- Performs local health checks and leader election

**Cilium (Data Plane)**
- Handles pod networking and CNI responsibilities
- Advertises pod CIDRs via BGP
- Manages LoadBalancer service IPs
- Provides network policy enforcement

## BGP Configuration

### No Session Conflicts

kube-vip and Cilium run **separate, independent BGP sessions** to peer routers:
- Each component runs its own BGP daemon
- Both establish distinct TCP connections to the same peer router(s)
- Router sees two separate BGP neighbor sessions from each node
- Sessions are differentiated by AS number and/or BGP Router ID

### Recommended AS Configuration

**Use different AS numbers for maximum simplicity and compatibility:**
```
kube-vip:     AS 65001
Cilium:       AS 65002
Router/ToR:   AS 65000 (or your network AS)
```

**Benefits of separate AS numbers:**
- Zero ambiguity - clear neighbor identification
- No Router ID conflicts
- Standard eBGP practice
- Maximum router compatibility
- Easy troubleshooting and route attribution

**AS number selection:**
- Use private AS range: 64512-65534 (16-bit) or 4200000000-4294967294 (32-bit)
- Choose consecutive numbers for easier management

### BGP Session Example

From a single Kubernetes node perspective:
```
Node IP: 10.0.1.5

kube-vip BGP session:
  Local: 10.0.1.5:54321 → Peer: 10.0.0.1:179 (AS 65001)
  Advertises: 192.168.1.100/32 (control plane VIP)

Cilium BGP session:
  Local: 10.0.1.5:54322 → Peer: 10.0.0.1:179 (AS 65002)
  Advertises: 10.244.1.0/24 (pod CIDR)
              192.168.200.50/32 (LoadBalancer service)
```

Router configuration:
```
neighbor 10.0.1.5 remote-as 65001    # kube-vip
neighbor 10.0.1.5 remote-as 65002    # Cilium
```

## kube-vip Operation Modes

### ARP Mode vs BGP Mode

**ARP Mode:**
- Leader binds VIP to local interface
- Responds to ARP requests with its MAC address
- Requires all control plane nodes on same L2 network
- Uses gratuitous ARP on failover
- Simple but limited to flat L2 networks

**BGP Mode (Recommended):**
- Leader advertises VIP as /32 host route via BGP
- Works across L3 boundaries (different subnets/VLANs)
- Faster, more predictable failover
- Scalable and cloud-friendly
- Integrates with modern spine-leaf architectures

### Leader Election and Health Checks

**How kube-vip manages the VIP:**

1. **Leader Election**
   - Uses Kubernetes native leader election (lease-based in etcd)
   - One kube-vip pod becomes leader across all control plane nodes
   - Leader takes ownership of VIP advertisement

2. **Local Health Checks**
   - TCP probe to localhost:6443 (API server)
   - Default interval: 5 seconds
   - If health check fails → node voluntarily releases leadership
   - Ensures only nodes with working API server advertise VIP

3. **Failover Process**
   - Leader fails health check or loses connectivity
   - New leader elected automatically
   - New leader advertises VIP via its BGP session
   - BGP convergence typically <1 second

## Deployment Architecture

### Static Pod Deployment (Control Plane)

**Why static pods for control plane VIP:**
- Solves bootstrapping problem (runs before API server is accessible)
- Managed directly by kubelet, not API server
- Survives API server failures
- No chicken-and-egg dependency

**Installation process:**

1. Place manifest in kubelet's static pod directory:
```
   /etc/kubernetes/manifests/kube-vip.yaml
```

2. Kubelet automatically detects and starts the pod

3. No `kubectl apply` required

**Static pod characteristics:**
- Managed by kubelet directly
- Mirror pod appears in API for visibility (read-only)
- Cannot be deleted via kubectl (delete file to remove)
- Name includes node suffix (e.g., `kube-vip-controlplane1`)

### Multi-Node Control Plane Setup
```
Control Plane Node 1 (10.0.1.5)          Control Plane Node 2 (10.0.1.6)
┌─────────────────────┐                  ┌─────────────────────┐
│ kube-vip (LEADER)   │                  │ kube-vip (follower) │
│ - Static Pod        │                  │ - Static Pod        │
│ - BGP AS 65001      │                  │ - BGP AS 65001      │
│ - Advertises VIP    │                  │ - Silent (no advert)│
│ - Health: ✓         │                  │ - Health: ✓         │
├─────────────────────┤                  ├─────────────────────┤
│ Cilium Agent        │                  │ Cilium Agent        │
│ - BGP AS 65002      │                  │ - BGP AS 65002      │
│ - Advertises Pods   │                  │ - Advertises Pods   │
└─────────────────────┘                  └─────────────────────┘
         │ BGP                                    │ BGP
         └────────────────┬───────────────────────┘
                          │
                   ┌──────▼──────┐
                   │   Router    │
                   │  AS 65000   │
                   └─────────────┘
                   Routes:
                   192.168.1.100/32 → 10.0.1.5 (control plane VIP)
                   10.244.1.0/24 → 10.0.1.5 (pods)
                   10.244.2.0/24 → 10.0.1.6 (pods)
```

## Failure Scenarios

### Total Control Plane Failure

**What happens:**
- If all control plane nodes fail health checks, VIP disappears
- No failsafe mechanism - this is by design
- BGP mode: All nodes stop advertising, route withdrawn
- ARP mode: No ARP responses, traffic dropped

**Why this is correct:**
- Fail closed rather than route to broken API server
- Clear failure signal for monitoring
- Prevents split-brain scenarios
- Better to be unavailable than inconsistent

### Mitigation Strategies

1. **Proper HA Architecture**
   - Minimum 3 control plane nodes
   - Spread across failure domains (racks/AZs)
   - Anti-affinity rules prevent co-location
   - Redundant network/power infrastructure

2. **Multi-Layer Monitoring**
   - External synthetic checks to VIP:6443
   - Alert on control plane degradation (<2 healthy nodes)
   - Monitor kube-vip leader status
   - Separate etcd health monitoring

3. **Automated Recovery**
   - Auto-restart failed nodes/VMs
   - Infrastructure-level health checks
   - Disaster recovery runbooks

## Configuration Examples

### kube-vip Static Pod Manifest
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - name: kube-vip
    image: ghcr.io/kube-vip/kube-vip:latest
    args:
    - manager
    env:
    - name: vip_interface
      value: "eth0"
    - name: vip_address
      value: "192.168.1.100"
    - name: cp_enable
      value: "true"
    - name: bgp_enable
      value: "true"
    - name: bgp_routerid
      value: "192.168.1.100"
    - name: bgp_as
      value: "65001"
    - name: bgp_peers
      value: "10.0.0.1:65000:65000,10.0.0.2:65000:65000"
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostNetwork: true
  volumes:
  - name: kubeconfig
    hostPath:
      path: /etc/kubernetes/admin.conf
```

### Router Configuration Example
```
# Cisco IOS-style
router bgp 65000
 neighbor 10.0.1.5 remote-as 65001
 neighbor 10.0.1.5 description kube-vip-node1
 neighbor 10.0.1.5 remote-as 65002
 neighbor 10.0.1.5 description cilium-node1
 !
 neighbor 10.0.1.6 remote-as 65001
 neighbor 10.0.1.6 description kube-vip-node2
 neighbor 10.0.1.6 remote-as 65002
 neighbor 10.0.1.6 description cilium-node2
```

## Benefits of This Architecture

1. **Clear Separation of Concerns**
   - Control plane HA (kube-vip) separate from data plane (Cilium)
   - Independent upgrade paths
   - Isolated failure domains

2. **L3 Routed Network Support**
   - No reliance on L2 adjacency
   - Works across datacenter boundaries
   - Cloud and on-premises compatible

3. **Fast, Predictable Failover**
   - BGP convergence typically sub-second
   - Deterministic routing behavior
   - Easy to test and verify

4. **Operational Simplicity**
   - Standard BGP practices
   - Compatible with existing network infrastructure
   - Clear troubleshooting (route attribution per component)

5. **Scalability**
   - Works with spine-leaf architectures
   - ECMP support for data plane traffic
   - No L2 domain limitations

## Monitoring and Observability

### Key Metrics to Monitor
```yaml
# Control plane health
- kube-vip leader election status
- API server VIP reachability
- Control plane node count (minimum 2)

# BGP health
- BGP session state (Established)
- Route advertisement counts
- BGP flap detection

# Performance
- API server response time via VIP
- BGP convergence time on failover
- Health check success rate
```

### Recommended Alerts
```yaml
- Alert: ControlPlaneDegraded
  Condition: Healthy control plane nodes < 2
  Severity: Critical

- Alert: APIServerVIPDown  
  Condition: VIP not responding to health checks
  Severity: Critical

- Alert: KubeVipNoLeader
  Condition: No kube-vip leader elected
  Severity: Warning

- Alert: BGPSessionDown
  Condition: BGP neighbor state != Established
  Severity: Warning
```

## Summary

This architecture provides a robust, scalable solution for Kubernetes control plane high availability using industry-standard BGP routing. The separation of control plane (kube-vip) and data plane (Cilium) BGP sessions offers clear operational boundaries while leveraging the same underlying network infrastructure. Using different AS numbers ensures maximum compatibility and simplifies troubleshooting.

**Key Decisions:**
- ✅ kube-vip in BGP mode for control plane VIP
- ✅ Separate AS numbers (65001 for kube-vip, 65002 for Cilium)
- ✅ Static pod deployment for control plane
- ✅ Minimum 3 control plane nodes across failure domains
- ✅ External monitoring of VIP and BGP sessions

**Next Steps:**
1. Configure BGP peering on network infrastructure
2. Deploy kube-vip as static pods on control plane nodes
3. Configure Cilium BGP for pod and service advertisement
4. Implement monitoring and alerting
5. Test failover scenarios
6. Document disaster recovery procedures