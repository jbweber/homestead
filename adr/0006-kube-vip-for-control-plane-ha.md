---
status: accepted
date: 2025-11-10
---

# kube-vip for Control Plane HA

## Context and Problem Statement

High availability Kubernetes clusters require a single stable endpoint (VIP - Virtual IP) for the API server that remains available even when individual control plane nodes fail. Clients and worker nodes need to communicate with the control plane through this VIP rather than individual node IPs. How should the control plane VIP be implemented for bare metal Kubernetes clusters?

## Decision Drivers

* High availability - VIP must failover when active node fails
* Simplicity - Minimize additional infrastructure requirements
* Bare metal compatibility - Must work without cloud provider load balancers
* Network architecture - Integration with existing L2/L3 network
* Bootstrap requirements - VIP needed before cluster fully operational
* Resource efficiency - Minimal overhead for HA capability

## Considered Options

* **Option 1**: kube-vip in ARP mode (L2)
* **Option 2**: kube-vip in BGP mode (L3)
* **Option 3**: HAProxy + Keepalived on external nodes
* **Option 4**: MetalLB for control plane VIP
* **Option 5**: Hardware load balancer

## Decision Outcome

Chosen option: **"kube-vip in ARP mode (L2)"**, because it provides simple control plane VIP functionality without requiring BGP infrastructure or external load balancer nodes, suitable for environments where control plane nodes share a single L2 network segment.

The implementation uses:
- kube-vip as static pod on each control plane node
- ARP mode for VIP advertisement (Layer 2)
- Leader election determines which node holds VIP
- Deployed via preKubeadmCommands in KubeadmControlPlane
- VIP configured before cluster bootstrap

### Consequences

* Good, because no external load balancer infrastructure required
* Good, because works in L2 network environments (common for bare metal)
* Good, because deployed as static pod (no dependency on cluster services)
* Good, because automatic failover via leader election
* Good, because minimal resource overhead (single container per control plane node)
* Good, because integrates cleanly with kubeadm bootstrap process
* Bad, because limited to single L2 network segment (ARP limitations)
* Bad, because ARP-based failover slower than BGP (seconds vs sub-second)
* Bad, because requires control plane nodes on same VLAN
* Neutral, because appropriate for small-medium clusters on single L2 domain
* Neutral, because BGP mode available if network architecture changes

### Confirmation

This decision is validated through operational experience:
1. kube-vip successfully providing control plane VIP for multi-node clusters
2. API server accessible via VIP from worker nodes and external clients
3. Failover working correctly (VIP moves to different node during control plane maintenance)
4. Bootstrap process reliable (VIP available before kubeadm init completes)
5. Zero external dependencies (no external load balancers or keepalived nodes)

## Pros and Cons of the Options

### Option 1: kube-vip in ARP mode (L2)

* Good, because simple L2 solution (no BGP infrastructure needed)
* Good, because works on standard switched networks
* Good, because deploys as static pod (no external dependencies)
* Good, because automatic failover via leader election
* Good, because minimal resource overhead
* Bad, because limited to single L2 network segment
* Bad, because ARP-based failover slower than BGP
* Bad, because all control plane nodes must be on same VLAN
* Neutral, because appropriate for typical bare metal deployments

### Option 2: kube-vip in BGP mode (L3)

* Good, because works across L3 boundaries (routed networks)
* Good, because faster failover than ARP
* Good, because more scalable for large deployments
* Good, because integrates with network routing infrastructure
* Bad, because requires BGP-capable network infrastructure
* Bad, because more complex configuration (BGP peering)
* Bad, because not needed for small-medium clusters on single L2 segment
* Neutral, because future option if network architecture evolves

### Option 3: HAProxy + Keepalived on external nodes

* Good, because proven traditional HA pattern
* Good, because works across different network architectures
* Good, because external to Kubernetes (independent lifecycle)
* Bad, because requires dedicated external nodes (2+ for HA)
* Bad, because additional infrastructure to maintain
* Bad, because more complex configuration (HAProxy, Keepalived)
* Bad, because adds failure domain (external load balancers themselves)
* Bad, because resource overhead for dedicated nodes

### Option 4: MetalLB for control plane VIP

* Good, because mature L2/BGP load balancer
* Good, because handles both control plane and service VIPs
* Bad, because requires running cluster to function (chicken-and-egg problem)
* Bad, because control plane VIP needed before cluster exists
* Bad, because designed for service load balancing, not control plane HA
* Bad, because adds complexity for control plane use case
* Neutral, because better suited for service LoadBalancers, not control plane VIP

### Option 5: Hardware load balancer

* Good, because enterprise-grade reliability
* Good, because high performance
* Good, because independent of cluster lifecycle
* Bad, because expensive hardware investment
* Bad, because not available in most small-medium deployments
* Bad, because adds operational complexity (hardware management)
* Bad, because overkill for small-medium cluster scale

## More Information

This decision was made based on requirements for:
- High availability control plane in bare metal environment
- No external load balancer infrastructure available
- Control plane nodes on same L2 network segment
- Simple operational model with minimal dependencies
- Small to medium cluster scale (3-5 control plane nodes)

kube-vip deployment pattern:
```yaml
# In KubeadmControlPlane preKubeadmCommands
preKubeadmCommands:
  - mkdir -p /etc/kubernetes/manifests
  - ctr image pull ghcr.io/kube-vip/kube-vip:v0.7.0
  - ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:v0.7.0 vip \
    /kube-vip manifest pod \
    --interface eth0 \
    --address 192.168.1.100 \
    --controlplane \
    --arp \
    --leaderElection > /etc/kubernetes/manifests/kube-vip.yaml
```

Key configuration points:
- **VIP address**: Assigned to control plane endpoint
- **Interface**: Network interface for ARP announcements
- **ARP mode**: L2 advertisement of VIP
- **Leader election**: Determines which node holds VIP
- **Static pod**: Runs before cluster fully operational

Bootstrap sequence:
1. preKubeadmCommands create kube-vip manifest on all control plane nodes
2. kubelet starts kube-vip as static pod
3. Leader election determines initial VIP holder
4. VIP available for kubeadm init/join operations
5. Cluster bootstrap proceeds with VIP as API endpoint

Failover behavior:
- Leader election continuously monitors control plane health
- VIP moves to different node if leader fails
- ARP announcements update network about new VIP location
- Failover typically completes within seconds
- API server remains accessible during failover

When to reconsider:
- Control plane nodes span multiple L2 segments (use BGP mode)
- Network supports BGP and faster failover desired
- Cluster scale increases significantly (dozens of clusters)
- Enterprise hardware load balancers become available

Related decisions:
- ADR-0005: Cluster Architecture Pattern (HA requires 3+ control plane nodes)
- ADR-0008: Network Configuration Approach (VIP must be on control plane network)
- ADR-0009: CNI Selection (Cilium) - Critical: CNI must use VIP as k8sServiceHost
