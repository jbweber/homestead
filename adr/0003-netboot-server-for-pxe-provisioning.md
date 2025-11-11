---
status: accepted
date: 2025-11-10
---

# Netboot Server for PXE Provisioning

## Context and Problem Statement

Metal3 requires bare metal hosts to network boot (PXE/iPXE) to provision operating system images. This requires DHCP and HTTP services to deliver boot artifacts. How should these network boot services be deployed to support Metal3 provisioning while maintaining reliability and network independence?

## Decision Drivers

* Network independence - Avoid tight coupling with management cluster lifecycle
* Service reliability - Netboot services must remain available during cluster operations
* Operational simplicity - Minimize infrastructure components
* Bootstrap dependencies - Enable initial management cluster creation
* Infrastructure requirements - DHCP and HTTP service hosting
* Network architecture - Integration with existing network infrastructure

## Considered Options

* **Option 1**: Dedicated netboot server (separate from management cluster)
* **Option 2**: Netboot services on management cluster
* **Option 3**: Netboot services on workload cluster nodes
* **Option 4**: Managed netboot service (cloud/SaaS)
* **Option 5**: Existing network infrastructure (router/switch DHCP + file server)

## Decision Outcome

Chosen option: **"Dedicated netboot server (separate from management cluster)"**, because it provides network independence, avoids circular dependencies during management cluster bootstrap, and ensures netboot services remain available regardless of management cluster state.

The netboot server runs:
- dnsmasq for DHCP and TFTP services
- HTTP server for serving OS images and cloud-init data
- Independent of Kubernetes cluster lifecycle
- Minimal resource requirements (can run on small VM or physical host)

### Consequences

* Good, because netboot services remain available during management cluster maintenance
* Good, because no circular dependency during management cluster bootstrap
* Good, because simple failure domain separation (network services vs cluster services)
* Good, because minimal resource requirements (single small VM/host)
* Good, because can serve multiple management clusters if needed
* Good, because network configuration changes don't require cluster operations
* Bad, because requires one additional server/VM beyond management cluster
* Bad, because another service to maintain and monitor
* Neutral, because DHCP service may conflict with existing network DHCP (requires coordination)
* Neutral, because requires network architecture planning (which subnet provides DHCP)

### Confirmation

This decision is validated through operational experience:
1. Netboot server successfully serving PXE requests for bare metal provisioning
2. Management cluster can be rebuilt without affecting netboot infrastructure
3. Workload clusters provisioned successfully using netboot services
4. Network boot services remain stable during cluster operations
5. Single netboot server handles provisioning for multiple workload clusters

## Pros and Cons of the Options

### Option 1: Dedicated netboot server (separate from management cluster)

* Good, because independent lifecycle from management cluster
* Good, because no circular dependencies during bootstrap
* Good, because network services isolated from cluster operations
* Good, because minimal resource requirements
* Good, because can serve multiple clusters
* Good, because simpler failure domain analysis
* Bad, because requires additional infrastructure (one more host/VM)
* Bad, because another component to maintain
* Neutral, because DHCP coordination needed with existing network

### Option 2: Netboot services on management cluster

* Good, because consolidates infrastructure (no separate server)
* Good, because Kubernetes-native service management
* Bad, because circular dependency during management cluster bootstrap
* Bad, because management cluster downtime affects provisioning capability
* Bad, because cluster upgrades/maintenance require careful netboot service handling
* Bad, because ties network infrastructure to cluster lifecycle
* Bad, because complex failure scenarios (netboot services down = can't rebuild management cluster)

### Option 3: Netboot services on workload cluster nodes

* Good, because no dedicated infrastructure needed
* Bad, because circular dependency (can't provision first cluster)
* Bad, because workload cluster issues affect provisioning
* Bad, because inappropriate mixing of concerns
* Bad, because workload cluster lifecycle shouldn't control infrastructure services

### Option 4: Managed netboot service (cloud/SaaS)

* Good, because offloads operational burden
* Good, because high availability from provider
* Bad, because introduces external dependency for on-premises infrastructure
* Bad, because may require internet connectivity for bare metal provisioning
* Bad, because potential latency for image transfers
* Bad, because ongoing costs
* Bad, because limited control over service configuration
* Bad, because security concerns (PXE boot artifacts accessible externally)

### Option 5: Existing network infrastructure (router/switch DHCP + file server)

* Good, because leverages existing infrastructure
* Good, because no additional servers needed
* Good, because network team may already manage DHCP
* Bad, because tight coupling with network infrastructure
* Bad, because Metal3-specific configuration on network devices
* Bad, because may not have sufficient control over DHCP options
* Bad, because file server requirements may not align with network team tools
* Bad, because changes require coordination across teams
* Neutral, because depends heavily on existing infrastructure capabilities

## More Information

This decision was made based on requirements for:
- Reliable bare metal provisioning independent of cluster state
- Ability to rebuild management cluster from scratch
- Clear separation between network infrastructure and cluster infrastructure
- Minimal additional operational complexity

The netboot server provides essential services:
- **DHCP**: Assigns IPs and provides PXE boot options (next-server, boot filename)
- **TFTP**: Delivers initial boot loader (iPXE)
- **HTTP**: Serves OS images, kernel, initrd, and cloud-init configurations
- **Image hosting**: Stores OS images prepared for Metal3 provisioning

Network architecture considerations:
- Netboot server typically on management network (same L2 domain as BMC/provisioning network)
- DHCP coordination with existing network infrastructure required
- May use DHCP relay if netboot server on different subnet
- HTTP service accessible from nodes during provisioning

Bootstrap sequence:
1. Netboot server must be operational before management cluster creation
2. Management cluster uses netboot services during its own deployment
3. Workload clusters use netboot services for provisioning
4. Netboot server operates independently throughout all cluster lifecycles

Related decisions:
- ADR-0000: Bare Metal Provisioning Approach (Metal3 requires network boot capability)
- ADR-0002: Metal3 Management Cluster Architecture (netboot server separate from management cluster)
- ADR-0004: Sushy-tools for Redfish Emulation (BMC integration for triggering network boot)
