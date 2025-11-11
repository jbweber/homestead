---
status: accepted
date: 2025-11-10
---

# Bare Metal Provisioning Approach

## Context and Problem Statement

Managing Kubernetes clusters on bare metal infrastructure requires tooling for automated provisioning, lifecycle management, and declarative configuration. How should bare metal Kubernetes clusters be provisioned and managed to balance automation capabilities, operational complexity, and alignment with upstream Kubernetes patterns?

## Decision Drivers

* Declarative infrastructure management - GitOps-compatible approach
* Lifecycle management - Support for cluster creation, scaling, upgrades, and deletion
* Bare metal focus - Native support for physical hardware provisioning
* Upstream alignment - Follow Kubernetes community patterns and standards
* Automation capabilities - Reduce manual intervention in cluster operations
* Operational complexity - Balance sophistication against maintainability
* Portability - Potential to extend beyond bare metal to heterogeneous infrastructure

## Considered Options

* **Option 1**: Cluster API with Metal3 provider (CAPM3)
* **Option 2**: Manual kubeadm deployment
* **Option 3**: Rancher
* **Option 4**: Talos
* **Option 5**: kubespray/kubeone
* **Option 6**: Infrastructure-as-code tools (Terraform/Ansible)

## Decision Outcome

Chosen option: **"Cluster API with Metal3 provider (CAPM3)"**, because it provides declarative, lifecycle-aware cluster management with native bare metal support while following upstream Kubernetes patterns and enabling future multi-provider scenarios.

The implementation uses:
- Cluster API core controllers for cluster lifecycle
- Metal3 infrastructure provider (CAPM3) for bare metal provisioning
- Baremetal Operator and Ironic for hardware management
- Kubeadm bootstrap/control plane providers for cluster initialization

### Consequences

* Good, because infrastructure is managed declaratively via Kubernetes resources
* Good, because cluster lifecycle operations (create, scale, upgrade, delete) are standardized
* Good, because it follows official Kubernetes subproject patterns (Cluster API is a CNCF project)
* Good, because Metal3 provides native bare metal provisioning without cloud provider dependencies
* Good, because the same management cluster can potentially support multiple infrastructure providers
* Good, because GitOps workflows are naturally supported
* Good, because upgrades and scaling are handled through resource updates rather than manual procedures
* Bad, because it requires a management cluster (bootstrapping complexity)
* Bad, because learning curve is steeper than manual approaches
* Bad, because additional components increase system complexity (CAPI controllers, Ironic, baremetal-operator)
* Neutral, because operational knowledge transfers to other Cluster API providers
* Neutral, because troubleshooting requires understanding multiple abstraction layers

### Confirmation

This decision is validated through successful implementation:
1. Management cluster successfully provisioning workload clusters from bare metal
2. Cluster lifecycle operations (creation, scaling, deletion) working end-to-end
3. Declarative cluster definitions maintained in git
4. Cluster upgrades performed through manifest updates rather than manual intervention
5. Infrastructure changes applied through GitOps patterns

## Pros and Cons of the Options

### Option 1: Cluster API with Metal3 provider

* Good, because declarative infrastructure management via Kubernetes resources
* Good, because standardized cluster lifecycle across different infrastructure types
* Good, because follows upstream Kubernetes community patterns (CNCF project)
* Good, because Metal3 provides native bare metal provisioning
* Good, because supports GitOps workflows naturally
* Good, because enables future heterogeneous infrastructure scenarios
* Good, because lifecycle operations (scale, upgrade) are built-in
* Bad, because requires dedicated management cluster (bootstrapping overhead)
* Bad, because multiple abstraction layers increase complexity
* Bad, because steeper learning curve than manual approaches
* Bad, because troubleshooting requires understanding CAPI + Metal3 + Ironic stack

### Option 2: Manual kubeadm deployment

* Good, because minimal abstraction (direct Kubernetes cluster creation)
* Good, because well-documented upstream approach
* Good, because no additional infrastructure required
* Good, because easy to understand for Kubernetes practitioners
* Bad, because no lifecycle management (scaling/upgrades are manual procedures)
* Bad, because not declarative (requires imperative commands)
* Bad, because difficult to maintain consistency across multiple clusters
* Bad, because no GitOps integration
* Bad, because cluster-to-cluster configuration drift likely

### Option 3: Rancher

* Good, because provides UI and API for cluster management
* Good, because supports multiple infrastructure providers
* Good, because includes monitoring and policy management
* Bad, because introduces vendor-specific patterns
* Bad, because adds additional management layer (RKE/RKE2)
* Bad, because less alignment with upstream Kubernetes patterns
* Bad, because Rancher itself requires management infrastructure
* Bad, because bare metal support less mature than cloud providers

### Option 4: Talos

* Good, because immutable OS designed for Kubernetes
* Good, because API-driven configuration (no SSH)
* Good, because minimal attack surface
* Good, because declarative configuration via machine configs
* Bad, because requires adoption of Talos-specific OS and patterns
* Bad, because less ecosystem support than kubeadm-based approaches
* Bad, because opinionated approach may conflict with specific requirements
* Bad, because smaller community than Cluster API
* Neutral, because paradigm shift from traditional Linux administration - worth exploring but delayed for immediate progression

### Option 5: kubespray/kubeone

* Good, because Ansible-based automation (familiar tooling)
* Good, because supports multiple infrastructure types
* Good, because mature and well-tested
* Bad, because imperative approach (Ansible playbooks vs declarative resources)
* Bad, because lifecycle operations require playbook execution
* Bad, because GitOps integration less natural than CAPI
* Bad, because cluster state not represented as Kubernetes resources
* Bad, because configuration drift requires external tooling to detect

### Option 6: Infrastructure-as-code tools (Terraform/Ansible)

* Good, because familiar tooling for infrastructure teams
* Good, because can manage non-Kubernetes infrastructure alongside clusters
* Good, because mature ecosystem and community
* Bad, because lifecycle management requires custom implementation
* Bad, because not Kubernetes-native (state external to Kubernetes)
* Bad, because cluster upgrades require custom automation
* Bad, because no standardized patterns for cluster lifecycle
* Bad, because GitOps integration requires additional tooling

## More Information

This decision was made after evaluating requirements for:
- Small to medium-scale bare metal deployments (2-10 workload clusters)
- Declarative infrastructure management compatible with GitOps
- Standardized cluster lifecycle operations
- Alignment with upstream Kubernetes community practices
- Future flexibility for heterogeneous infrastructure

Cluster API with Metal3 represents the upstream Kubernetes community's approach to bare metal cluster lifecycle management. While it introduces additional complexity compared to manual approaches, the declarative model and standardized lifecycle operations provide long-term operational benefits.

The Metal3 project specifically addresses bare metal provisioning challenges:
- Hardware inventory and management (BareMetalHost resources)
- PXE/iPXE network booting
- BMC/Redfish integration for power management
- Integration with Ironic for bare metal orchestration

Related decisions:
- ADR-0002: Metal3 Management Cluster Architecture (how to deploy the management cluster)
- ADR-0003: Netboot Server for PXE Provisioning (infrastructure required for Metal3)
- ADR-0004: Sushy-tools for Redfish Emulation (BMC integration for development/testing)
- Future: Heterogeneous infrastructure providers (see adr/TODO.md) - CAPI's multi-provider capability influenced this decision
