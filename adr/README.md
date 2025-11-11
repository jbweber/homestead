# Architecture Decision Records (ADR)

This directory contains Architecture Decision Records (ADRs) documenting the key decisions made in building the homelab infrastructure stack using Cluster API and Metal3.

## Format

ADRs follow the [MADR (Markdown Any Decision Records)](https://adr.github.io/madr/) format. See [TEMPLATE.md](TEMPLATE.md) for the structure.

## Naming Convention

ADRs are numbered sequentially with a 4-digit prefix:
- `0001-title-of-decision.md`
- `0002-another-decision.md`

## Index

### Provisioning Approach
- [ADR-0000](0000-bare-metal-provisioning-approach.md) - Bare Metal Provisioning Approach (Cluster API + Metal3)

### Foundation Layer
- [ADR-0002](0002-metal3-management-cluster-architecture.md) - Metal3 Management Cluster Architecture
- [ADR-0003](0003-netboot-server-for-pxe-provisioning.md) - Netboot Server for PXE Provisioning
- [ADR-0004](0004-sushy-tools-for-redfish-emulation.md) - Sushy-tools for Redfish Emulation

### Cluster API Decisions
- [ADR-0005](0005-cluster-api-provider-selection.md) - Cluster API Provider Selection (Metal3)
- [ADR-0006](0006-cluster-architecture-pattern.md) - Cluster Architecture Pattern (KubeadmControlPlane + MachineDeployment)
- [ADR-0007](0007-kube-vip-for-control-plane-ha.md) - kube-vip for Control Plane HA

### Networking Decisions
- [ADR-0008](0008-network-configuration-approach.md) - Network Configuration Approach (BMH networkData)
- [ADR-0009](0009-cni-selection-cilium.md) - CNI Selection (Cilium)
- [ADR-0010](0010-bgp-routing-with-cilium.md) - BGP Routing with Cilium

### Deployment & Tooling
- [ADR-0011](0011-cilium-deployment-via-clusterresourceset.md) - Cilium Deployment via ClusterResourceSet
- [ADR-0012](0012-image-building-with-kiwi.md) - Image Building with KIWI

## Status Legend

- **Proposed** - Decision under consideration
- **Accepted** - Decision approved and implemented
- **Deprecated** - No longer recommended, superseded by newer approach
- **Rejected** - Decision considered but not accepted
- **Superseded** - Replaced by a newer ADR

## Related Documentation

- [PLAN_HOMESTEAD.md](../PLAN_HOMESTEAD.md) - Current status and roadmap
- [capi/TODO.md](../capi/TODO.md) - Known issues and future improvements
- [docs/cilium-install.md](../docs/cilium-install.md) - Cilium installation patterns
