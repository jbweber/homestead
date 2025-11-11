---
status: accepted
date: 2025-11-10
---

# Metal3 Management Cluster Architecture

## Context and Problem Statement

Metal3 and Cluster API require a Kubernetes cluster to operate as the management plane for provisioning bare metal infrastructure. This management cluster hosts the controllers that orchestrate cluster lifecycle operations. How should this management cluster be architected to balance resource efficiency, operational complexity, and reliability requirements for small to medium-scale bare metal deployments?

## Decision Drivers

* Resource efficiency - Minimize overhead for management infrastructure
* Operational simplicity - Reduce complexity in managing the management plane itself
* Reliability requirements - Balance availability needs against operational cost
* Separation of concerns - Maintain clear boundary between management and workload planes
* Bootstrap complexity - Avoid circular dependencies in cluster creation
* Scale expectations - Typical deployment manages 2-10 workload clusters

## Considered Options

* **Option 1**: Single-node Kubernetes cluster dedicated to management
* **Option 2**: Multi-node HA management cluster (3+ nodes)
* **Option 3**: Managed Kubernetes service (cloud provider)
* **Option 4**: Local cluster on operator workstation (kind/k3d)
* **Option 5**: Shared cluster (management and workload combined)

## Decision Outcome

Chosen option: **"Single-node Kubernetes cluster dedicated to management"**, because it provides the optimal balance of resource efficiency and operational simplicity for small to medium-scale deployments while maintaining proper separation of concerns.

The management cluster runs as a single-node Kubernetes cluster with:
- Standard Kubernetes distribution (kubeadm-based)
- Metal3 components (baremetal-operator, ironic)
- Cluster API core and infrastructure providers
- Sufficient resources to manage expected workload cluster count

### Consequences

* Good, because resource overhead is minimal (single node vs 3+ for HA)
* Good, because operational complexity is reduced (no quorum management, no load balancer configuration)
* Good, because separation of concerns is maintained (independent lifecycle from workload clusters)
* Good, because it can be backed up and restored independently
* Good, because it scales adequately for small to medium deployments (validated managing multiple 3-5 node clusters)
* Bad, because management cluster downtime prevents new cluster provisioning and modifications
* Neutral, because existing workload clusters continue operating independently if management cluster is unavailable (CAPI manages provisioning, not runtime)
* Neutral, because recovery procedures are simpler than HA cluster (restore from backup without quorum concerns)

### Confirmation

This decision is validated through operational experience:
1. Single-node management cluster successfully provisioning and managing multiple workload clusters
2. Resource utilization remaining sustainable (sub-50% CPU/memory during normal operations)
3. Workload cluster independence verified - existing clusters remain fully operational during management cluster maintenance
4. End-to-end reprovisioning validated - complete cluster lifecycle operations working correctly

## Pros and Cons of the Options

### Option 1: Single-node Kubernetes cluster dedicated to management

* Good, because minimal resource footprint (1 node vs 3+ for HA)
* Good, because operationally simple (no distributed consensus, no load balancing)
* Good, because clear separation between management and workload planes
* Good, because independent backup/restore lifecycle
* Good, because adequate for small-medium scale (2-10 workload clusters)
* Bad, because single point of failure for provisioning operations
* Neutral, because workload clusters operate independently (downtime only affects new provisioning)

### Option 2: Multi-node HA management cluster

* Good, because provides high availability for management operations
* Good, because eliminates single point of failure
* Bad, because requires 3x minimum resources (etcd quorum requirement)
* Bad, because significantly increased operational complexity (distributed consensus, load balancing, certificate management)
* Bad, because overkill for small-medium scale deployments
* Bad, because recovery procedures more complex (quorum restoration)

### Option 3: Managed Kubernetes service

* Good, because provider handles availability and operations
* Good, because offloads operational burden
* Bad, because introduces ongoing costs
* Bad, because creates external dependency for on-premises infrastructure
* Bad, because potential latency for management operations
* Bad, because requires internet connectivity for infrastructure provisioning

### Option 4: Local cluster on operator workstation

* Good, because trivial to create/destroy
* Good, because minimal resource usage
* Bad, because ties management operations to workstation availability
* Bad, because workstation lifecycle affects infrastructure operations
* Bad, because complicates remote management scenarios
* Bad, because not suitable for production or team environments

### Option 5: Shared cluster (management and workload combined)

* Good, because eliminates separate infrastructure
* Bad, because creates circular dependency (cluster manages itself)
* Bad, because workload issues can impact management capabilities
* Bad, because violates separation of concerns principle
* Bad, because complicates cluster lifecycle operations (deletion, upgrades)
* Bad, because resource contention between management and workload responsibilities

## More Information

This decision was made after evaluating requirements for deployments managing 2-10 workload clusters where:
- Management operations (cluster creation, scaling, upgrades) occur infrequently (weekly to monthly)
- Acceptable recovery time for management cluster is measured in hours, not minutes
- Resource efficiency is prioritized over absolute high availability
- Workload cluster independence provides inherent resilience (management downtime doesn't affect running workloads)

The single-node approach is recommended by the Metal3 community for small-scale deployments and has proven effective in production use. For larger-scale deployments managing dozens of clusters with frequent provisioning operations, Option 2 (HA management cluster) becomes more appropriate despite the increased complexity.

Related decisions:
- ADR-0000: Bare Metal Provisioning Approach (why Metal3 + CAPI was chosen)
- ADR-0003: Netboot server architecture (separate from management cluster for network independence)
- ADR-0004: Redfish/BMC emulation approach (deployment location relative to management cluster)
- Future: Heterogeneous infrastructure providers (see adr/TODO.md) - may influence HA requirements
