# Metal3 Cluster API Configuration Guide

## Overview

This guide summarizes approaches for managing Cluster API clusters using the Metal3 provider, specifically addressing:
- Mixed hardware configurations
- Per-node network configuration
- Static IP assignment
- Configuration generation and templating

## Your Two Setups

### Setup 1: Mixed Hardware (3 VMs + 1 Baremetal)
- 3 virtual machine-based control plane nodes
- 1 baremetal worker node
- All provisioned via Metal3 with different configs due to hardware differences

### Setup 2: Homogeneous Hardware (8 Nodes)
- 8 identical nodes (same hardware)
- Different network configurations for each node
- All use static networking after DHCP provisioning and VLAN hopping

## Configuration Approaches

### Option A: Templates + MachineDeployments (For Homogeneous Groups)

**Best for:** Nodes that share the same configuration

**Structure:**
```yaml
KubeadmControlPlane (manages multiple control plane nodes)
  ↓
Metal3MachineTemplate (shared template)
  ↓
Metal3DataTemplate (shared network config)
  ↓
IPPool (can be shared or individual)
```

**Pros:**
- Less YAML to maintain
- Automatic scaling with replicas
- Cluster API manages lifecycle

**Cons:**
- All nodes must share the same Metal3MachineTemplate
- Limited per-node customization
- Network configs must be identical (or use variables)

**Example:**
```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta2
kind: KubeadmControlPlane
metadata:
  name: super
spec:
  replicas: 3
  machineTemplate:
    spec:
      infrastructureRef:
        kind: Metal3MachineTemplate
        name: super-controlplane
  # ... kubeadm config
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: super-controlplane
spec:
  template:
    spec:
      dataTemplate:
        name: super-shared-network
      # ... image config
```

### Option B: Individual Machine Resources (For Mixed Configs)

**Best for:** Each node needs unique configuration

**Structure:**
```yaml
Machine (per node)
  ↓
KubeadmConfig (per node)
Metal3Machine (per node)
  ↓
Metal3DataTemplate (per node)
IPPool (per node for static IPs)
```

**Pros:**
- Complete per-node control
- Different hardware configurations
- Node-specific network configs
- Explicit static IP assignment

**Cons:**
- More YAML to maintain
- No automatic scaling
- Manual lifecycle management

**Example:**
```yaml
apiVersion: cluster.x-k8s.io/v1beta2
kind: Machine
metadata:
  name: super-cp-node1
  labels:
    cluster.x-k8s.io/cluster-name: super
    cluster.x-k8s.io/control-plane: ""
spec:
  clusterName: super
  version: v1.34.1
  bootstrap:
    configRef:
      kind: KubeadmConfig  # Not KubeadmConfigTemplate
      name: super-cp-node1-config
  infrastructureRef:
    kind: Metal3Machine  # Not Metal3MachineTemplate
    name: super-cp-node1-machine
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta2
kind: KubeadmConfig
metadata:
  name: super-cp-node1-config
spec:
  initConfiguration:  # or joinConfiguration
    nodeRegistration:
      name: super-cp-node1
      kubeletExtraArgs:
        - name: node-labels
          value: node=node1
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3Machine
metadata:
  name: super-cp-node1-machine
spec:
  hostSelector:
    matchLabels:
      node: node1  # Matches BareMetalHost label
  dataTemplate:
    name: super-cp-node1-network
  image:
    url: http://netboot.cofront.xyz/fedora-43-ext4-k8s.raw
    checksum: http://netboot.cofront.xyz/fedora-43-ext4-k8s.raw.sha256sum
    checksumType: sha256
    format: raw
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3DataTemplate
metadata:
  name: super-cp-node1-network
spec:
  clusterName: super
  networkData:
    # Node-specific network configuration
---
apiVersion: ipam.metal3.io/v1alpha1
kind: IPPool
metadata:
  name: super-cp-node1-pool
spec:
  clusterName: super
  pools:
    - start: 172.31.255.186
      end: 172.31.255.186  # Single static IP
      prefix: 24
      gateway: 172.31.255.1
  dnsServers:
    - 172.31.255.1
```

### Option C: Hybrid Approach (Recommended for Setup 1)

**Best for:** Mix of homogeneous and heterogeneous nodes

**For Setup 1 (3 VMs + 1 Baremetal):**
- Use KubeadmControlPlane with Metal3MachineTemplate for 3 VMs (if they're similar)
- Use individual Machine resource for the baremetal worker

```yaml
# KubeadmControlPlane manages 3 VM control planes
apiVersion: controlplane.cluster.x-k8s.io/v1beta2
kind: KubeadmControlPlane
spec:
  replicas: 3
  machineTemplate:
    spec:
      infrastructureRef:
        kind: Metal3MachineTemplate
        name: super-controlplane-vms
---
# Individual Machine for baremetal worker
apiVersion: cluster.x-k8s.io/v1beta2
kind: Machine
metadata:
  name: super-worker-baremetal
spec:
  bootstrap:
    configRef:
      kind: KubeadmConfig
      name: super-worker-baremetal-config
  infrastructureRef:
    kind: Metal3Machine
    name: super-worker-baremetal-machine
```

## Network Configuration: MAC Addresses

### The MAC Address Question

**TL;DR: MAC addresses are likely NOT required if interface names are consistent**

### When MAC Addresses Are Needed:
- Multiple interfaces of the same type need disambiguation
- Interface naming is inconsistent across nodes
- Hardware has unpredictable interface enumeration

### When You Can Skip MAC Addresses:
- Interface names are consistent (`eno1`, `eno3`, etc.)
- Predictable interface naming (biosdevname, systemd naming)
- Using interface names is sufficient for your setup

### Without MAC Addresses (Simplified):

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3DataTemplate
metadata:
  name: super-shared-network
spec:
  clusterName: super
  networkData:
    links:
      ethernets:
        - type: phy
          id: eno1
          # No macAddress field
        - type: phy
          id: eno3
          # No macAddress field
      bonds:
        - id: bond0
          bondMode: active-backup
          bondLinks:
            - eno1
            - eno3
          # No macAddress - will use primary interface's MAC
          bondXmitHashPolicy: layer2
          parameters:
            miimon: 100
      vlans:
        - id: bond0.2000
          vlanID: 2000
          vlanLink: bond0
    networks:
      ipv4:
        - id: mgmt
          link: bond0.2000
          ipAddressFromIPPool: super-node-pool
          routes:
            - network: "0.0.0.0"
              prefix: 0
              gateway:
                fromIPPool: super-node-pool
    services:
      dns:
        - "172.31.255.1"
```

### With MAC Addresses (Your Current Approach):

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3DataTemplate
metadata:
  name: super-controlplane-template
spec:
  clusterName: super
  networkData:
    links:
      ethernets:
        - type: phy
          id: eno1
          macAddress:
            string: "3c:ec:ef:43:1c:6e"
        - type: phy
          id: eno3
          macAddress:
            string: "3c:ec:ef:43:1c:70"
      bonds:
        - id: bond0
          bondMode: active-backup
          bondLinks:
            - eno1
            - eno3
          macAddress:
            string: "3c:ec:ef:43:1c:6e"
          # ... rest of config
```

**Note:** This requires per-node Metal3DataTemplates since MAC addresses are unique.

## Recommendations by Setup

### Setup 1: 3 VMs + 1 Baremetal

**Recommended Approach: Hybrid (Option C)**

1. **For 3 VM Control Planes:**
   - Use KubeadmControlPlane with `replicas: 3`
   - Single Metal3MachineTemplate (VMs likely have similar config)
   - Single Metal3DataTemplate (if network config is shared)
   - Try without MAC addresses first

2. **For 1 Baremetal Worker:**
   - Individual Machine resource
   - Individual Metal3Machine
   - Individual Metal3DataTemplate (custom network config)
   - Individual IPPool for static IP

**Resources needed:**
- 1 Cluster
- 1 Metal3Cluster
- 1 KubeadmControlPlane
- 1 Metal3MachineTemplate (for VMs)
- 1 Metal3DataTemplate (for VMs, if config is shared)
- 1 Machine (for baremetal worker)
- 1 KubeadmConfig (for baremetal worker)
- 1 Metal3Machine (for baremetal worker)
- 1 Metal3DataTemplate (for baremetal worker)
- 2-4 IPPools (depending on whether VMs share or have individual IPs)

### Setup 2: 8 Identical Nodes

**Recommended Approach: Simplified with Shared Network Config**

**If MAC addresses are NOT needed:**

1. Create ONE Metal3DataTemplate with interface names only
2. Create EIGHT IPPools (one per node with static IP)
3. Use either:
   - Option A: KubeadmControlPlane (for control plane) + MachineDeployment (for workers)
   - Option B: 8 individual Machines for full control

**Key insight:** If interface names are consistent and you skip MAC addresses, you can share a single Metal3DataTemplate across all nodes. Only the IPPool needs to be per-node for static IPs.

**Resources needed (if using shared DataTemplate):**
- 1 Cluster
- 1 Metal3Cluster
- 1 KubeadmControlPlane (for control planes)
- 1 Metal3MachineTemplate (shared)
- 1 Metal3DataTemplate (shared network config)
- 8 IPPools (one per node)
- 0-1 MachineDeployment (if you have workers)

**If MAC addresses ARE required:**

Use Option B (Individual Machines) with per-node resources:
- 8 Machines
- 8 KubeadmConfigs
- 8 Metal3Machines (with hostSelector to bind to specific BareMetalHosts)
- 8 Metal3DataTemplates
- 8 IPPools

## Configuration Generation & Management

### Understanding clusterctl generate

`clusterctl generate cluster` is a **scaffolding tool**, not a production workflow:
- Uses templates from infrastructure provider (CAPM3 for Metal3)
- Does simple variable substitution (`${CLUSTER_NAME}`, `${KUBERNETES_VERSION}`, etc.)
- Generates basic, generic manifests
- **Purpose**: Show you the structure and required resources

**When to use it:**
- First time exploring CAPI/Metal3 - learn what resources are needed
- Understanding relationships between resources
- Getting started with a new provider

**When NOT to use it:**
- Production deployments with custom requirements
- Clusters needing kube-vip, custom networking, specific CNI, etc.
- After you've established your patterns and requirements

### The Problem with Repeated Generation

Once you need custom configs (which you always will), you're stuck in a loop:
1. Generate manifest
2. Edit extensively (networking, CNI, VIP, users, etc.)
3. Deploy
4. Need to change something
5. Regenerate? Now you lose your customizations
6. Or hand-edit the deployed manifest and lose sync with generation

### Better Approaches

#### Option 1: Create Your Own Template (Recommended)

Create a complete template file with all your resources:

```bash
# cluster-template.yaml contains EVERYTHING:
# - Cluster, Metal3Cluster
# - KubeadmControlPlane or Machines
# - Metal3MachineTemplates/Metal3Machines
# - Metal3DataTemplates
# - IPPools
# - etc.

# Generate once:
clusterctl generate cluster super \
  --from cluster-template.yaml \
  --kubernetes-version v1.34.1 \
  --control-plane-machine-count 3 \
  --worker-machine-count 5 \
  > super-cluster.yaml

# Apply:
kubectl apply -f super-cluster.yaml
```

**Variables you can use:**
- `${CLUSTER_NAME}`
- `${NAMESPACE}`
- `${KUBERNETES_VERSION}`
- `${CONTROL_PLANE_MACHINE_COUNT}`
- `${WORKER_MACHINE_COUNT}`
- Custom variables via environment variables

**Pros:**
- One command to generate complete config
- Version controlled template
- Minimal variables for truly variable things

**Cons:**
- Need to maintain template
- Still need to edit generated YAML for changes

#### Option 2: Direct YAML Maintenance (Simplest)

For 1-2 clusters, just maintain the complete YAML directly:

```bash
# super-cluster.yaml has EVERYTHING
# No templating, no generation, just apply

kubectl apply -f super-cluster.yaml
```

**Pros:**
- Simple, direct
- No build process
- Easy to understand what you have

**Cons:**
- No DRY for multiple similar clusters
- Manual updates for version changes

#### Option 3: Kustomize Overlays

Use Kustomize for base configs with overlays:

```
clusters/
├── base/
│   ├── kustomization.yaml
│   ├── cluster.yaml
│   ├── metal3cluster.yaml
│   └── kubeadmcontrolplane.yaml
├── setup1/
│   ├── kustomization.yaml
│   ├── vm-controlplanes.yaml
│   └── baremetal-worker.yaml
└── setup2/
    ├── kustomization.yaml
    └── 8-node-configs.yaml
```

**Apply with:**
```bash
kubectl apply -k clusters/setup1/
```

**Pros:**
- DRY principle
- Easy to manage variants
- Native Kubernetes tool

**Cons:**
- Learning curve for Kustomize
- Can get complex with many patches

#### Option 4: Helm Charts

Create a Helm chart for your cluster configs:

```
metal3-cluster/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── cluster.yaml
    ├── metal3cluster.yaml
    ├── machines.yaml
    └── datatemplates.yaml
```

**Pros:**
- Powerful templating
- Values file for configuration
- Can package and share

**Cons:**
- Overkill for simple cases
- Helm learning curve
- Debugging template issues

#### Option 5: GitOps (Flux/ArgoCD)

Store manifests in Git, let Flux/Argo apply them:

```
clusters/
├── super/
│   ├── cluster.yaml
│   ├── machines.yaml
│   └── network-configs.yaml
└── production/
    └── ...
```

**Pros:**
- Git as source of truth
- Automatic sync
- Audit trail

**Cons:**
- Additional infrastructure
- More complex setup
- Learning curve

### Recommended Workflow

**For your use case (2 different setups, not many clusters):**

1. **Create two complete template files:**
   - `cluster-setup1.yaml` (3 VMs + 1 baremetal)
   - `cluster-setup2.yaml` (8 nodes)

2. **Use minimal or no templating:**
   - Hard-code most values since they're specific to your hardware
   - Use variables only for truly variable things like cluster name or K8s version

3. **Generate once, then maintain directly:**
   ```bash
   # Initial generation (optional)
   clusterctl generate cluster super \
     --from cluster-setup1.yaml \
     --kubernetes-version v1.34.1 > super-cluster.yaml
   
   # After that, just edit super-cluster.yaml directly
   # Commit to Git
   # Apply when ready
   ```

4. **Version control everything:**
   ```
   git/
   ├── clusters/
   │   ├── super-setup1.yaml
   │   └── super-setup2.yaml
   └── README.md
   ```

**You don't need to keep regenerating** - that's mainly for when you're iterating on the template design or when using dynamic variables.

## Quick Reference: Resource Types

### Templates (for shared configs):
- `Metal3MachineTemplate` - Shared infrastructure spec
- `KubeadmConfigTemplate` - Shared bootstrap config
- `Metal3DataTemplate` - Network configuration

### Instances (for per-node configs):
- `Machine` - Individual machine (not from template)
- `Metal3Machine` - Individual infrastructure spec
- `KubeadmConfig` - Individual bootstrap config

### Controllers:
- `KubeadmControlPlane` - Manages multiple control plane nodes
- `MachineDeployment` - Manages multiple worker nodes

### Supporting:
- `Cluster` - Top-level cluster definition
- `Metal3Cluster` - Metal3-specific cluster config
- `IPPool` - IP address pool for Metal3 IPAM
- `BareMetalHost` - Represents physical hardware (managed by Metal3)

## Testing Your Simplified Setup

### Steps to Test Removing MAC Addresses:

1. **Create a test Metal3DataTemplate without MAC addresses**
2. **Apply it to one node first**
3. **Check if provisioning succeeds**
4. **If it works, use shared template for all 8 nodes in Setup 2**

### If it doesn't work:

- Check Metal3 version (older versions may require MACs)
- Verify interface naming consistency across nodes
- Check Metal3/Ironic logs for specific errors
- Consider whether bonding specifically requires MAC specification

## Summary: Decision Tree

### For Setup 1 (3 VMs + 1 Baremetal):

```
Do VMs have similar network configs?
├─ Yes → Use KubeadmControlPlane + shared Metal3MachineTemplate for VMs
│         + Individual Machine for baremetal
└─ No  → Use 4 individual Machines (one per node)
```

### For Setup 2 (8 Identical Nodes):

```
Are interface names consistent?
├─ Yes → Try removing MAC addresses
│        ├─ Works? → Use shared Metal3DataTemplate + 8 IPPools
│        │           (Templates + MachineDeployment OR individual Machines)
│        └─ Fails → Use 8 Metal3DataTemplates with MAC addresses
│                    (Individual Machines approach)
└─ No  → Use 8 Metal3DataTemplates with MAC addresses
         (Individual Machines approach)
```

### For Config Management:

```
How many clusters?
├─ 1-2 → Maintain complete YAML directly (no templating)
├─ 3-5 → Use own templates + clusterctl generate
└─ 5+  → Consider Kustomize or GitOps
```

## Next Steps

1. **Test MAC address removal** on one node in Setup 2
2. **If successful**, simplify to shared Metal3DataTemplate
3. **Choose config management approach** based on your workflow
4. **Document your final approach** for team members
5. **Version control everything** in Git

## Additional Resources

- Metal3 Documentation: https://metal3.io/
- Cluster API Book: https://cluster-api.sigs.k8s.io/
- Metal3DataTemplate Spec: https://github.com/metal3-io/ip-address-manager
- OpenStack network_data.json format: https://docs.openstack.org/nova/latest/user/metadata.html