---
status: accepted
date: 2025-11-10
---

# Network Configuration Approach

## Context and Problem Statement

Bare metal nodes provisioned by Metal3 require network configuration (IP addresses, routes, VLANs, bonds) before joining a Kubernetes cluster. Network configuration must be applied early in the provisioning process and persist across reboots. How should network configuration be delivered to bare metal nodes during Metal3 provisioning workflows?

## Decision Drivers

* Configuration timing - Network needed before cluster join operations
* Persistence - Configuration must survive reboots
* Complexity support - Handle simple and complex configs (bonds, VLANs)
* Metal3 integration - Work within Metal3/CAPI provisioning workflow
* Separation of concerns - Network config independent of cluster config
* Per-node customization - Different nodes may need different network configs

## Considered Options

* **Option 1**: BareMetalHost networkData (OpenStack network_data.json format)
* **Option 2**: Cloud-init network configuration in user-data
* **Option 3**: PostKubeadmCommands with nmcli/netplan
* **Option 4**: PreKubeadmCommands with nmcli/netplan
* **Option 5**: DHCP-only (no static configuration)

## Decision Outcome

Chosen option: **"BareMetalHost networkData (OpenStack network_data.json format)"**, because it separates network configuration from cluster bootstrap configuration, preserves network settings when nodes are reclaimed by CAPI, and supports both simple and complex network topologies through a standardized format.

The implementation uses:
- Per-node network configuration in Kubernetes Secret (OpenStack network_data.json format)
- BareMetalHost `spec.networkData` references the secret
- Network config applied during provisioning before cluster join
- Configuration persists independently of cluster lifecycle
- Same approach works for simple IPs and complex bonds/VLANs

### Consequences

* Good, because network configuration separated from cluster bootstrap
* Good, because CAPI preserves network config when claiming BMH (doesn't overwrite)
* Good, because supports complex configurations (bonds, VLANs, multiple interfaces)
* Good, because standardized format (OpenStack network_data.json)
* Good, because configuration applied before cluster operations begin
* Good, because per-node customization via separate secrets
* Good, because network config persists across cluster deletion/recreation
* Bad, because requires creating secret per node with unique network config
* Bad, because OpenStack format has learning curve
* Neutral, because network config stored in Metal3 management cluster (same as other BMH config)

### Confirmation

This decision is validated through operational experience:
1. Simple network configs (single interface, static IP) working correctly
2. Complex network configs (bonds, VLANs) working correctly
3. Network configuration applied before kubeadm join
4. Configuration persists across reboots
5. Cluster deletion and recreation preserves network settings
6. Multi-node clusters with different per-node network configs

## Pros and Cons of the Options

### Option 1: BareMetalHost networkData (OpenStack network_data.json format)

* Good, because separates network config from cluster config
* Good, because CAPI-aware (preserves config when claiming BMH)
* Good, because supports complex configurations
* Good, because standardized format (widely used in OpenStack)
* Good, because applied at provisioning time (before cluster join)
* Good, because per-node customization via secrets
* Good, because survives cluster lifecycle operations
* Bad, because requires creating secrets per node
* Bad, because OpenStack format learning curve
* Neutral, because managed in Metal3 cluster like other BMH config

### Option 2: Cloud-init network configuration in user-data

* Good, because standard cloud-init approach
* Good, because familiar format for cloud users
* Bad, because mixed with cluster bootstrap config (user-data)
* Bad, because CAPI may overwrite user-data when claiming BMH
* Bad, because harder to separate network concerns from cluster concerns
* Bad, because less clear lifecycle (network config tied to bootstrap)

### Option 3: PostKubeadmCommands with nmcli/netplan

* Good, because simple scripting approach
* Good, because flexible (any networking tool)
* Bad, because runs after kubeadm join (network already needed)
* Bad, because wrong timing for network configuration
* Bad, because imperative scripts vs declarative config
* Bad, because not suitable for network config that must exist before cluster join

### Option 4: PreKubeadmCommands with nmcli/netplan

* Good, because runs before kubeadm join (correct timing)
* Good, because flexible scripting
* Bad, because imperative approach (scripts vs declarative)
* Bad, because mixed with cluster bootstrap config
* Bad, because CAPI may overwrite when claiming BMH
* Bad, because harder to maintain and version control
* Bad, because requires careful script idempotency

### Option 5: DHCP-only (no static configuration)

* Good, because simplest approach (no config needed)
* Good, because works for simple networks
* Bad, because doesn't support complex configs (bonds, VLANs)
* Bad, because external DHCP dependency
* Bad, because IP assignments not stable/predictable
* Bad, because not suitable for production clusters
* Bad, because limited to single interface configurations

## More Information

This decision was made based on requirements for:
- Static IP addressing for cluster nodes
- Complex network configurations (bonds, VLANs) in some environments
- Network configuration independent of cluster lifecycle
- Per-node network customization
- CAPI-compatible provisioning workflow

OpenStack network_data.json format example (simple):
```json
{
  "links": [
    {
      "id": "eth0",
      "type": "phy",
      "ethernet_mac_address": "52:54:00:xx:xx:xx"
    }
  ],
  "networks": [
    {
      "id": "network0",
      "type": "ipv4",
      "link": "eth0",
      "ip_address": "192.168.1.10",
      "netmask": "255.255.255.0",
      "routes": [
        {
          "network": "0.0.0.0",
          "netmask": "0.0.0.0",
          "gateway": "192.168.1.1"
        }
      ]
    }
  ],
  "services": [
    {
      "type": "dns",
      "address": "8.8.8.8"
    }
  ]
}
```

Complex configuration support (bonds, VLANs):
- Bond interfaces for redundancy
- VLAN tagging for network segmentation
- Multiple network interfaces
- Static routes beyond default gateway
- MTU configuration

Configuration workflow:
1. Create Secret with network_data.json for each node
2. Reference secret in BareMetalHost `spec.networkData.name`
3. Metal3 applies network config during provisioning
4. Network configuration persists independently
5. CAPI claims BMH without modifying network config
6. Cluster join operations use configured network

CAPI integration:
- BareMetalHost created with networkData before CAPI involvement
- CAPI creates Cluster/Machine resources referencing BMH
- Metal3 provisions node with network config from BMH
- CAPI doesn't modify BMH networkData (preserved across cluster lifecycle)
- Cluster deletion doesn't affect BMH network configuration

Related decisions:
- ADR-0000: Bare Metal Provisioning Approach (Metal3 handles node provisioning)
- ADR-0005: Cluster Architecture Pattern (nodes provisioned via templates)
- ADR-0006: kube-vip for Control Plane HA (VIP must be on configured network)
- ADR-0009: CNI Selection (pod networking independent of node networking)
