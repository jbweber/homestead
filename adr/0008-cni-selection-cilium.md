---
status: accepted
date: 2025-11-10
---

# CNI Selection (Cilium)

## Context and Problem Statement

Kubernetes requires a Container Network Interface (CNI) plugin to provide pod networking, network policies, and service load balancing. The CNI choice significantly impacts cluster performance, observability, and available networking features. Which CNI should be deployed for bare metal Kubernetes clusters to balance performance, features, and operational complexity?

## Decision Drivers

* Performance - Efficient packet processing for bare metal workloads
* Feature set - Network policies, observability, service mesh capabilities
* Bare metal optimization - Native routing without unnecessary encapsulation
* BGP integration - Pod CIDR advertisement to network infrastructure
* Operational maturity - Production-ready with active community
* kube-proxy replacement - Reduce resource overhead and improve performance
* Future capabilities - Room for growth (service mesh, advanced policies)

## Considered Options

* **Option 1**: Cilium with eBPF and BGP support
* **Option 2**: Calico with BGP
* **Option 3**: Flannel (simple overlay)
* **Option 4**: Multus + secondary CNI
* **Option 5**: kube-router

## Decision Outcome

Chosen option: **"Cilium with eBPF and BGP support"**, because it provides high-performance eBPF-based networking with native routing, BGP integration for bare metal environments, kube-proxy replacement capabilities, and advanced observability features while remaining production-ready and actively developed.

The implementation uses:
- Cilium CNI with kube-proxy replacement enabled
- Native routing mode (no VXLAN/Geneve tunnels)
- BGP control plane for pod CIDR advertisement
- eBPF for packet processing and network policies
- Kubeadm configured to skip kube-proxy installation

### Consequences

* Good, because eBPF-based packet processing provides excellent performance
* Good, because native routing mode optimal for bare metal (no encapsulation overhead)
* Good, because BGP integration enables infrastructure-wide pod routing
* Good, because kube-proxy replacement reduces resource usage and latency
* Good, because advanced observability via Hubble
* Good, because production-ready with large community and enterprise backing
* Good, because room for growth (service mesh, advanced policies, multi-cluster)
* Good, because active development and regular releases
* Bad, because more complex than simple CNIs (Flannel)
* Bad, because requires kernel 4.9+ for eBPF features
* Bad, because learning curve for eBPF concepts and Cilium-specific features
* Neutral, because BGP configuration required for optimal bare metal integration

### Confirmation

This decision is validated through operational experience:
1. Cilium successfully providing pod networking for multi-node clusters
2. Native routing mode working without tunnels (verified via packet captures)
3. BGP control plane advertising pod CIDRs to network infrastructure
4. kube-proxy-free cluster operation validated
5. Network policies functioning correctly
6. Performance meets bare metal workload requirements
7. Hubble observability providing valuable network insights

## Pros and Cons of the Options

### Option 1: Cilium with eBPF and BGP support

* Good, because high-performance eBPF packet processing
* Good, because native routing mode (no encapsulation)
* Good, because BGP integration for bare metal
* Good, because kube-proxy replacement
* Good, because advanced observability (Hubble)
* Good, because network policy support
* Good, because service mesh capabilities available
* Good, because production-ready with enterprise backing
* Good, because active development community
* Bad, because more complex than simpler CNIs
* Bad, because requires modern kernel (4.9+)
* Bad, because learning curve for eBPF concepts

### Option 2: Calico with BGP

* Good, because mature BGP implementation
* Good, because proven in bare metal environments
* Good, because strong network policy support
* Good, because doesn't require eBPF (wider kernel compatibility)
* Good, because good documentation and community
* Bad, because uses iptables (higher overhead than eBPF)
* Bad, because less advanced observability than Cilium
* Bad, because kube-proxy still required
* Neutral, because traditional networking approach (more familiar but less performant)

### Option 3: Flannel (simple overlay)

* Good, because extremely simple to deploy
* Good, because minimal configuration required
* Good, because lightweight
* Good, because low learning curve
* Bad, because VXLAN overlay adds latency and complexity
* Bad, because no BGP support (not optimal for bare metal)
* Bad, because limited network policy support
* Bad, because no kube-proxy replacement
* Bad, because minimal observability features
* Bad, because limited feature set for production needs

### Option 4: Multus + secondary CNI

* Good, because multiple network interfaces per pod
* Good, because supports complex network requirements
* Bad, because adds significant complexity
* Bad, because requires primary CNI plus Multus
* Bad, because overkill for most use cases
* Bad, because more components to maintain
* Neutral, because valuable for specific use cases (telco, NFV) but not general purpose

### Option 5: kube-router

* Good, because all-in-one solution (CNI + service proxy + BGP)
* Good, because BGP support built-in
* Good, because designed for bare metal
* Bad, because smaller community than Cilium/Calico
* Bad, because less active development
* Bad, because fewer advanced features
* Bad, because uses iptables (not eBPF)
* Neutral, because simpler but less capable than Cilium

## More Information

This decision was made based on requirements for:
- High-performance networking for bare metal workloads
- Integration with network infrastructure via BGP
- Production-ready solution with strong community
- Advanced features for future growth (observability, service mesh)
- Efficient resource utilization (kube-proxy replacement)

Cilium deployment configuration:
- **Routing mode**: Native (no tunnels, direct routing)
- **IPAM**: Kubernetes host-scope (PodCIDR per node)
- **kube-proxy replacement**: Enabled (eBPF-based service handling)
- **BGP**: Cilium BGP v2 API for pod CIDR advertisement
- **Datapath**: eBPF for packet processing and policy enforcement

Key features utilized:
- **Native routing**: Direct packet forwarding without encapsulation
- **BGP integration**: Pod CIDRs advertised to ToR switches/routers
- **kube-proxy replacement**: eBPF-based service load balancing
- **Network policies**: eBPF-enforced L3/L4 and L7 policies
- **Hubble**: Flow observability and network debugging

Bootstrap considerations:
- Critical: Cilium must be configured with k8sServiceHost/Port pointing to control plane VIP
- Reason: Avoids chicken-and-egg problem during cluster bootstrap (Cilium needs to reach API server before CNI fully operational)
- Implementation: Set in Cilium Helm values during deployment

Performance characteristics:
- eBPF processing in kernel space (minimal context switching)
- No tunnel overhead (native routing)
- Efficient connection tracking
- Hardware offload capabilities (compatible NICs)

Future capabilities available:
- **Service mesh**: Cilium service mesh (eBPF-based, no sidecars)
- **Multi-cluster**: Cluster mesh for pod connectivity across clusters
- **Advanced policies**: DNS-aware, L7 HTTP/gRPC policies
- **Encryption**: Transparent encryption with WireGuard or IPsec
- **Observability**: Hubble UI and metrics for network flows

Related decisions:
- ADR-0006: kube-vip for Control Plane HA (Cilium must use VIP as k8sServiceHost)
- ADR-0007: Network Configuration Approach (node networking independent of pod networking)
- ADR-0009: BGP Routing with Cilium (how pod CIDRs advertised to infrastructure)
- ADR-0010: Cilium Deployment via ClusterResourceSet (how Cilium deployed to clusters)
