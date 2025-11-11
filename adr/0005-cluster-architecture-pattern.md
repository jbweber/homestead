---
status: accepted
date: 2025-11-10
---

# Cluster Architecture Pattern

## Context and Problem Statement

Cluster API supports multiple approaches for defining cluster topology: using templates with KubeadmControlPlane and MachineDeployment resources, or using individual Machine resources for each node. How should workload clusters be structured to balance flexibility, operational simplicity, and scalability for small to medium-scale bare metal deployments?

## Decision Drivers

* Operational simplicity - Minimize YAML complexity and management overhead
* Scalability - Easy cluster expansion and contraction
* Homogeneous infrastructure - Nodes with similar hardware specifications
* Template reusability - Patterns applicable across multiple clusters
* Cluster lifecycle management - Support for upgrades and modifications
* Mental model clarity - Understandable abstractions for operators

## Considered Options

* **Option 1**: KubeadmControlPlane + MachineDeployment (templates)
* **Option 2**: Individual Machine resources per node
* **Option 3**: MachineSet for homogeneous node groups
* **Option 4**: MachinePool (experimental)

## Decision Outcome

Chosen option: **"KubeadmControlPlane + MachineDeployment (templates)"**, because it provides declarative scaling, simplified YAML management, and built-in upgrade orchestration for homogeneous bare metal infrastructure.

The implementation uses:
- **KubeadmControlPlane**: Manages control plane nodes as a group (declarative replica count)
- **MachineDeployment**: Manages worker nodes as a group (declarative replica count)
- **Templates**: Shared configuration via Metal3MachineTemplate, KubeadmConfigTemplate
- **Scaling**: Change replica count to add/remove nodes

### Consequences

* Good, because scaling is declarative (change replica count, CAPI handles details)
* Good, because less YAML to manage (templates vs individual resources)
* Good, because built-in upgrade orchestration (rolling updates)
* Good, because mental model matches Kubernetes Deployments
* Good, because works well for homogeneous infrastructure (identical VMs or similar physical hosts)
* Good, because template reuse across clusters
* Bad, because less per-node customization (assumes similar nodes)
* Bad, because all nodes in group share same configuration
* Neutral, because works best when nodes have similar hardware/network config
* Neutral, because complex per-node configs require individual Machine resources

### Confirmation

This decision is validated through operational experience:
1. Multi-node HA cluster successfully deployed (3 control planes + 1 worker)
2. Worker nodes added to existing cluster by increasing MachineDeployment replicas
3. Cluster scaling operations working correctly (CAPI provisions new BMHs automatically)
4. Template pattern reduced YAML complexity vs individual Machines
5. Pattern works well for identical VMs and similar physical hardware

## Pros and Cons of the Options

### Option 1: KubeadmControlPlane + MachineDeployment (templates)

* Good, because declarative scaling (replica count changes)
* Good, because less YAML (templates reused)
* Good, because built-in rolling upgrade support
* Good, because familiar pattern (like Kubernetes Deployments)
* Good, because CAPI handles orchestration details
* Bad, because assumes homogeneous nodes
* Bad, because per-node customization limited
* Neutral, because best for similar hardware configurations

### Option 2: Individual Machine resources per node

* Good, because maximum per-node control
* Good, because explicit node configuration
* Good, because works for heterogeneous hardware
* Good, because clear what's deployed (no abstraction)
* Bad, because more YAML to manage (one resource per node)
* Bad, because scaling requires manual resource creation
* Bad, because upgrades require manual orchestration
* Bad, because more operational complexity

### Option 3: MachineSet for homogeneous node groups

* Good, because supports homogeneous node groups
* Good, because declarative replica count
* Bad, because less commonly used than MachineDeployment
* Bad, because MachineDeployment provides rolling update strategy
* Bad, because no significant advantage over MachineDeployment for this use case
* Neutral, because similar to MachineDeployment but less features

### Option 4: MachinePool (experimental)

* Good, because single resource represents multiple nodes
* Good, because potentially more efficient for large node counts
* Bad, because experimental/alpha status
* Bad, because limited provider support
* Bad, because less mature than MachineDeployment pattern
* Bad, because adoption premature for production use

## More Information

This decision was made based on requirements for:
- Small to medium-scale deployments (3-10 nodes per cluster)
- Homogeneous or similar hardware (identical VMs or standardized physical servers)
- Operational simplicity over maximum flexibility
- Standard Cluster API patterns and best practices

Typical cluster structure:
```yaml
# Control plane: KubeadmControlPlane with 3 replicas
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: cluster-name-control-plane
spec:
  replicas: 3
  machineTemplate:
    infrastructureRef:
      kind: Metal3MachineTemplate
      name: cluster-name-control-plane

# Workers: MachineDeployment with N replicas
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: cluster-name-workers
spec:
  replicas: 2
  template:
    spec:
      infrastructureRef:
        kind: Metal3MachineTemplate
        name: cluster-name-workers
      bootstrap:
        configRef:
          kind: KubeadmConfigTemplate
          name: cluster-name-workers
```

Scaling operations:
- **Scale up**: Increase replica count, CAPI provisions additional nodes
- **Scale down**: Decrease replica count, CAPI deprovisions nodes
- **Upgrade**: Update template, CAPI performs rolling update

When individual Machines are appropriate:
- Heterogeneous hardware (different CPU/RAM/storage per node)
- Complex per-node network configurations
- Special-purpose nodes requiring unique settings
- Maximum control over node lifecycle

Pattern variations:
- **Small cluster**: 1 control plane, 0-2 workers (development/testing)
- **HA cluster**: 3 control planes, 1+ workers (production)
- **Scaling**: Start small, increase replicas as needed

Related decisions:
- ADR-0000: Bare Metal Provisioning Approach (CAPI provides these abstractions)
- ADR-0002: Metal3 Management Cluster Architecture (where CAPI controllers run)
- ADR-0006: kube-vip for Control Plane HA (requires 3+ control plane replicas)
- ADR-0008: Network Configuration Approach (per-node configs use BMH networkData)
