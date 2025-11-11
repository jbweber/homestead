---
status: accepted
date: 2025-11-10
---

# BGP Routing with Cilium

## Context and Problem Statement

Pod networking in Kubernetes typically uses overlay networks (VXLAN/Geneve) or requires manual route distribution. For bare metal deployments with BGP-capable network infrastructure, pods can be made directly routable by advertising pod CIDRs via BGP. How should pod CIDR routing be integrated with network infrastructure to enable direct pod connectivity without overlay networks?

## Decision Drivers

* Native routing - Avoid tunnel overhead for bare metal performance
* Infrastructure integration - Leverage existing BGP-capable routers
* Scalability - Per-node pod CIDR advertisement
* Operational simplicity - Minimize manual route configuration
* Standard protocols - Use BGP (industry standard for route advertisement)
* Automation - Dynamic route updates as nodes join/leave cluster

## Considered Options

* **Option 1**: Cilium BGP control plane (BGP v2 API)
* **Option 2**: Static routes on network infrastructure
* **Option 3**: VXLAN/Geneve overlay (no BGP)
* **Option 4**: MetalLB for pod CIDR advertisement
* **Option 5**: kube-router BGP

## Decision Outcome

Chosen option: **"Cilium BGP control plane (BGP v2 API)"**, because it provides automated pod CIDR advertisement to network infrastructure using standard BGP protocol, integrates cleanly with Cilium CNI, and eliminates overlay network overhead for optimal bare metal performance.

The implementation uses:
- Cilium BGP v2 API (CiliumBGPClusterConfig, CiliumBGPPeerConfig, CiliumBGPAdvertisement)
- Each node advertises its allocated PodCIDR (/24 from cluster PodCIDR /16)
- BGP peering with upstream router/switch (ToR)
- Native routing mode (no tunnels)
- Automatic route updates as nodes join/leave

### Consequences

* Good, because pod CIDRs automatically advertised to network infrastructure
* Good, because native routing (no tunnel overhead)
* Good, because standard BGP protocol (interoperable with any BGP router)
* Good, because dynamic - routes added/removed as cluster scales
* Good, because leverages existing network infrastructure
* Good, because per-node PodCIDR advertisement (efficient route distribution)
* Good, because integrated with Cilium CNI (single component)
* Bad, because requires BGP-capable network infrastructure
* Bad, because BGP configuration on network devices required
* Bad, because additional complexity vs overlay networks
* Neutral, because appropriate for environments with BGP infrastructure

### Confirmation

This decision is validated through operational experience:
1. BGP peering sessions established between cluster nodes and router
2. Pod CIDRs advertised and accepted by upstream router
3. Direct pod-to-pod connectivity across nodes without tunnels
4. Routes automatically added when nodes join cluster
5. Routes automatically removed when nodes leave cluster
6. External services can reach pods directly (no NAT/overlay)
7. FRR peer-groups simplify router configuration

## Pros and Cons of the Options

### Option 1: Cilium BGP control plane (BGP v2 API)

* Good, because automated route advertisement
* Good, because integrated with Cilium CNI
* Good, because standard BGP protocol
* Good, because dynamic route updates
* Good, because native routing (no tunnels)
* Good, because modern API (v2 improves on v1)
* Bad, because requires BGP-capable infrastructure
* Bad, because BGP configuration needed on routers
* Neutral, because appropriate for BGP-enabled environments

### Option 2: Static routes on network infrastructure

* Good, because simple concept
* Good, because no BGP sessions needed
* Good, because native routing
* Bad, because completely manual route management
* Bad, because doesn't scale (manual updates per node)
* Bad, because error-prone (manual configuration)
* Bad, because no automation when nodes join/leave
* Bad, because operational burden increases with cluster size

### Option 3: VXLAN/Geneve overlay (no BGP)

* Good, because works without infrastructure changes
* Good, because simple deployment (overlay handles routing)
* Good, because no router configuration needed
* Bad, because tunnel overhead (encapsulation/decapsulation)
* Bad, because higher latency than native routing
* Bad, because higher CPU usage for tunnel processing
* Bad, because pods not directly routable from infrastructure
* Bad, because suboptimal for bare metal performance

### Option 4: MetalLB for pod CIDR advertisement

* Good, because BGP-capable
* Good, because handles route advertisement
* Bad, because MetalLB designed for LoadBalancer services, not pod CIDRs
* Bad, because adds component beyond CNI
* Bad, because redundant with Cilium BGP capability
* Bad, because more complex architecture (Cilium + MetalLB both doing BGP)
* Neutral, because MetalLB better suited for service LoadBalancer IPs

### Option 5: kube-router BGP

* Good, because built-in BGP support
* Good, because designed for pod CIDR advertisement
* Bad, because requires different CNI (switching from Cilium)
* Bad, because loses Cilium eBPF benefits
* Bad, because smaller community than Cilium
* Bad, because less feature-rich than Cilium
* Neutral, because viable if not using Cilium, but conflicts with ADR-0008

## More Information

This decision was made based on requirements for:
- Native routing for bare metal performance
- Existing BGP-capable network infrastructure
- Automated route management at cluster scale
- Direct pod reachability from network infrastructure
- Integration with Cilium CNI choice (ADR-0008)

Cilium BGP v2 API architecture:
- **CiliumBGPClusterConfig**: Cluster-wide BGP configuration
- **CiliumBGPPeerConfig**: BGP neighbor/peer definition
- **CiliumBGPAdvertisement**: What to advertise (PodCIDR in this case)
- Each node runs Cilium agent with BGP capability
- Per-node BGP session to upstream router(s)

Typical BGP configuration:
```yaml
# Cluster-wide BGP config
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
spec:
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/control-plane: ""
  bgpInstances:
  - name: main
    localASN: 65010
    peers:
    - name: router
      peerConfigRef:
        name: cilium-peer

# Peer configuration
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
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
        advertise: bgp

# Advertisement definition
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
  labels:
    advertise: bgp
spec:
  advertisements:
  - advertisementType: "PodCIDR"
```

Network infrastructure requirements:
- BGP-capable router/switch (ToR or distribution layer)
- Ability to peer with cluster nodes (reachable via management network)
- Route acceptance policy (allow pod CIDR ranges)
- Optional: FRR peer-groups for simplified configuration

FRR peer-group pattern (router configuration):
```
router bgp 65001
  neighbor CILIUM_NODES peer-group
  neighbor CILIUM_NODES remote-as 65010

  neighbor 192.168.1.10 peer-group CILIUM_NODES
  neighbor 192.168.1.11 peer-group CILIUM_NODES
  neighbor 192.168.1.12 peer-group CILIUM_NODES
```

Benefits: Simplifies router configuration from ~6 lines per node to 1 line per node

Route distribution:
- Each node allocated portion of cluster PodCIDR (e.g., /24 from /16)
- Node advertises only its own PodCIDR
- Router learns all pod routes from cluster
- Equal-cost multi-path (ECMP) not typically used (each node has unique prefix)

BGP session management:
- Cilium agent manages BGP lifecycle
- Automatic reconnection on network issues
- Graceful restart support for maintenance
- Health checking and route withdrawal on node failure

Alternative: BGP Unnumbered
- Uses link-local IPv6 for peering (no IP configuration needed)
- Simpler configuration, scales better
- Not yet supported by Cilium (tracked in issue #22132)
- Future consideration when available

Related decisions:
- ADR-0007: Network Configuration Approach (node networking separate from pod networking)
- ADR-0008: CNI Selection (Cilium chosen, provides BGP capability)
- ADR-0010: Cilium Deployment via ClusterResourceSet (how Cilium+BGP config deployed)
