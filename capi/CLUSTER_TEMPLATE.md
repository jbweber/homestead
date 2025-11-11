# Cluster Provisioning Template

This guide walks through creating a new Kubernetes cluster using the Metal3 + Cluster API infrastructure. It assumes you already have:

- Metal3 management cluster running
- BareMetalHosts registered and in `available` state
- OS images built and served via netboot server
- Network infrastructure configured (VLANs, BGP if applicable)

See [Architecture Decision Records](../adr/README.md) for the "why" behind these patterns.

## Quick Reference

**Templates:**
- [templates/simple/](templates/simple/) - Single control plane cluster (dev/testing)
- [templates/ha/](templates/ha/) - HA cluster (3 control planes + workers)
- [templates/examples/](templates/examples/) - Real-world example configurations

**Key Concepts:**
- **BareMetalHost (BMH)**: Represents physical or virtual machine inventory
- **networkData**: Per-node network configuration (pre-applied before CAPI claims)
- **ClusterResourceSet**: Automatically deploys CNI and other resources to new clusters
- **Labels**: Used to assign BMHs to clusters

## Directory Structure

For each cluster, create a directory with this structure:

```
my-cluster/
├── cluster.yaml                    # Cluster + Metal3Cluster
├── control-plane.yaml              # KubeadmControlPlane + Metal3MachineTemplate
├── workers.yaml                    # MachineDeployment + Metal3MachineTemplate + KubeadmConfigTemplate
├── network/
│   ├── node1-network.yaml          # Secret with networkData for node1
│   ├── node2-network.yaml          # Secret with networkData for node2
│   └── ...
├── cni/
│   ├── cilium-manifests.yaml      # Rendered Cilium manifests
│   └── cilium-crs.yaml             # ClusterResourceSet to deploy Cilium
└── bgp/                            # Optional: BGP configuration
    ├── cilium-bgp-cluster-config.yaml
    ├── cilium-bgp-peer-config.yaml
    └── cilium-bgp-advertisement.yaml
```

## Step-by-Step Workflow

### Prerequisites Check

Before starting, verify:

```bash
# Management cluster accessible
export KUBECONFIG=/path/to/metal3-kubeconfig.yaml
kubectl get nodes

# BareMetalHosts available
kubectl get bmh
# Should see hosts in 'available' state

# Images available on netboot server
curl http://netboot-server:8080/images/
# Should see your OS image

# ClusterAPI providers installed
kubectl get crd | grep cluster.x-k8s.io
kubectl get crd | grep infrastructure.cluster.x-k8s.io
```

### Step 0: Register BareMetalHosts (If Not Already Done)

If you haven't already registered your hardware as BareMetalHosts, do this first:

#### 0.1 Create BareMetalHost Resources

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-01
  namespace: default
spec:
  online: false  # Keep offline until ready to use
  bmc:
    address: redfish-virtualmedia://192.168.1.10:8000/redfish/v1/Systems/node-01
    credentialsName: node-01-bmc-secret
    disableCertificateVerification: true
  bootMACAddress: "52:54:00:11:22:33"
  # rootDeviceHints help Metal3 select correct disk
  rootDeviceHints:
    deviceName: "/dev/sda"  # OR use other hints below
    # minSizeGigabytes: 50
    # hctl: "0:0:0:0"
    # model: "SSD"
    # vendor: "ATA"
    # serialNumber: "ABC123"
---
apiVersion: v1
kind: Secret
metadata:
  name: node-01-bmc-secret
  namespace: default
type: Opaque
data:
  username: YWRtaW4=  # base64 encoded 'admin'
  password: cGFzc3dvcmQ=  # base64 encoded 'password'
```

**Key fields explained:**

- **online**: Set to `false` initially - prevents Metal3 from inspecting immediately
- **bmc.address**: Redfish/IPMI URL for BMC access
  - Format: `redfish-virtualmedia://HOST:PORT/redfish/v1/Systems/SYSTEM_ID`
  - Or IPMI: `ipmi://HOST:PORT`
- **bootMACAddress**: MAC address used for PXE boot
- **rootDeviceHints**: Tells Ironic which disk to use for OS installation

**rootDeviceHints options** (choose based on your hardware):

```yaml
rootDeviceHints:
  # By device name (simple, but may change)
  deviceName: "/dev/sda"

  # By size (useful for "use largest disk")
  minSizeGigabytes: 100

  # By hardware path (stable across reboots)
  hctl: "0:0:0:0"

  # By disk model/vendor
  model: "SAMSUNG"
  vendor: "ATA"

  # By serial number (most specific)
  serialNumber: "S3Z9NX0M123456"

  # WWN (World Wide Name)
  wwn: "0x50014ee2b5d59bb0"

  # Multiple hints (AND logic)
  minSizeGigabytes: 50
  rotational: false  # SSD only
```

**How to find disk information for rootDeviceHints:**

```bash
# SSH to the node (if accessible) or boot into rescue OS
lsblk -o NAME,SIZE,MODEL,SERIAL,WWN,HCTL

# Or use Ironic inspection data after first inspection
kubectl get bmh node-01 -o json | jq '.status.hardware Disks'
```

#### 0.2 Apply BareMetalHost and Wait for Inspection

```bash
# Apply BMH
kubectl apply -f baremetalhost.yaml

# Set BMH online to trigger inspection
kubectl patch bmh node-01 --type merge -p '{"spec":{"online":true}}'

# Watch inspection progress
watch kubectl get bmh node-01

# Inspection states:
# registering -> inspecting -> available
```

**Inspection process:**
1. Metal3 powers on host via BMC
2. Host PXE boots into Ironic Python Agent (IPA)
3. IPA discovers hardware (CPU, RAM, disks, NICs)
4. Hardware details stored in BMH status
5. Host powered off, BMH transitions to `available`

#### 0.3 Review Inspection Data

```bash
# View discovered hardware
kubectl get bmh node-01 -o yaml

# Check status.hardware for:
# - cpu (cores, model)
# - ramMebibytes
# - storage (disks with size, model, serial)
# - nics (MACs, speed)
```

**Use this data to:**
- Verify rootDeviceHints selected correct disk
- Get MAC addresses for bootMACAddress
- Understand hardware capabilities
- Plan network configuration

#### 0.4 Adjust rootDeviceHints if Needed

If inspection shows wrong disk selected:

```bash
# Update rootDeviceHints
kubectl patch bmh node-01 --type merge -p '{
  "spec": {
    "rootDeviceHints": {
      "serialNumber": "S3Z9NX0M123456"
    }
  }
}'

# Force re-inspection if needed
kubectl annotate bmh node-01 inspect.metal3.io="$(date +%s)"
```

#### 0.5 Set BMH to available State

Once inspection complete and rootDeviceHints correct:

```bash
# BMH should be in 'available' state
kubectl get bmh node-01 -o jsonpath='{.status.provisioning.state}'

# If not, check for errors
kubectl describe bmh node-01
```

**Repeat for all nodes** in your infrastructure.

### Step 1: Plan Your Cluster

Decide on:
- **Cluster name**: e.g., `prod-01`, `dev-cluster`
- **Node count**: How many control planes (1 or 3) and workers
- **Nodes to use**: Which BMHs (by name) for control plane vs workers
- **Network**: IP addresses, VLANs, gateway
- **CNI configuration**: Pod CIDR, service CIDR
- **Control plane VIP**: For HA clusters (kube-vip)
- **BGP**: AS numbers, peer IPs (if applicable)

### Step 2: Prepare BareMetalHosts for Cluster

#### 2.1 Create Network Configuration Secrets

For each node, create a secret with OpenStack network_data.json format:

```bash
# Example: Simple static IP configuration
cat > node1-network-data.json <<EOF
{
  "links": [
    {
      "id": "eth0",
      "type": "phy",
      "ethernet_mac_address": "52:54:00:11:22:33"
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
    },
    {
      "type": "dns",
      "address": "8.8.4.4"
    }
  ]
}
EOF

# Create secret in Metal3 management cluster
kubectl create secret generic my-cluster-node1-network \
  --from-file=networkData=node1-network-data.json \
  --namespace default
```

**For complex networking (bonds, VLANs)**, see [templates/examples/network-complex.yaml](templates/examples/network-complex.yaml).

#### 2.2 Update BareMetalHost with networkData

```bash
# Identify available BMHs
kubectl get bmh -o wide

# Update BMH with network configuration
kubectl patch bmh my-host-1 --type merge -p '{
  "spec": {
    "networkData": {
      "name": "my-cluster-node1-network",
      "namespace": "default"
    }
  }
}'

# Repeat for each node in your cluster
```

#### 2.3 Label BareMetalHosts for Cluster Assignment

```bash
# Label control plane nodes
kubectl label bmh my-host-1 cluster.x-k8s.io/cluster-name=my-cluster
kubectl label bmh my-host-1 cluster.x-k8s.io/role=control-plane

# Label worker nodes
kubectl label bmh my-host-4 cluster.x-k8s.io/cluster-name=my-cluster
kubectl label bmh my-host-4 cluster.x-k8s.io/role=worker

# Verify labels
kubectl get bmh -L cluster.x-k8s.io/cluster-name,cluster.x-k8s.io/role
```

### Step 3: Prepare CNI Deployment

#### 3.1 Render Cilium Manifests

```bash
# Render Cilium with your configuration
helm template cilium cilium/cilium \
  --namespace kube-system \
  --version 1.15.0 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<CONTROL_PLANE_VIP> \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set tunnel=disabled \
  --set ipv4NativeRoutingCIDR=<POD_CIDR> \
  --set autoDirectNodeRoutes=true \
  --set bgpControlPlane.enabled=true \
  > my-cluster-cilium.yaml
```

**CRITICAL**: Replace `<CONTROL_PLANE_VIP>` with your kube-vip VIP address. This prevents bootstrap chicken-and-egg problems.

#### 3.2 Create ConfigMap and ClusterResourceSet

```bash
# Create ConfigMap with Cilium manifests
kubectl create configmap my-cluster-cilium-manifests \
  --from-file=cilium.yaml=my-cluster-cilium.yaml \
  --namespace default

# Create ClusterResourceSet
cat > my-cluster-cilium-crs.yaml <<EOF
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: my-cluster-cilium
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      cni: cilium
      cluster-name: my-cluster
  resources:
  - name: my-cluster-cilium-manifests
    kind: ConfigMap
  strategy: ApplyOnce
EOF

kubectl apply -f my-cluster-cilium-crs.yaml
```

### Step 4: Create Cluster Manifests

Use templates from [templates/simple/](templates/simple/) or [templates/ha/](templates/ha/) as starting points.

**Key customizations needed:**

1. **Cluster name**: Replace `CLUSTER_NAME` throughout
2. **Network CIDRs**: Set podSubnet and service CIDR
3. **Control plane VIP**: kube-vip address (HA clusters)
4. **Image URL**: OS image location on netboot server
5. **Node counts**: Replicas for control plane and workers
6. **BMH selectors**: Labels to match your BMHs

#### 4.1 Edit cluster.yaml

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
  namespace: default
  labels:
    cni: cilium              # Matches ClusterResourceSet selector
    cluster-name: my-cluster # Matches ClusterResourceSet selector
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 10.244.0.0/16       # YOUR POD CIDR
    services:
      cidrBlocks:
      - 10.96.0.0/12        # YOUR SERVICE CIDR
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: my-cluster-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: Metal3Cluster
    name: my-cluster
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3Cluster
metadata:
  name: my-cluster
  namespace: default
spec:
  controlPlaneEndpoint:
    host: 192.168.1.100     # YOUR CONTROL PLANE VIP
    port: 6443
  noCloudProvider: true
```

#### 4.2 Edit control-plane.yaml

Key sections to customize:

```yaml
spec:
  replicas: 3  # 1 for simple, 3 for HA

  kubeadmConfigSpec:
    clusterConfiguration:
      controllerManager:
        extraArgs:
          bind-address: "0.0.0.0"
      scheduler:
        extraArgs:
          bind-address: "0.0.0.0"
      networking:
        podSubnet: "10.244.0.0/16"  # YOUR POD CIDR

    initConfiguration:
      skipPhases:
      - addon/kube-proxy  # Cilium replaces kube-proxy

    joinConfiguration:
      skipPhases:
      - addon/kube-proxy

    preKubeadmCommands:
    # kube-vip static pod setup
    - mkdir -p /etc/kubernetes/manifests
    - ctr image pull ghcr.io/kube-vip/kube-vip:v0.7.0
    - ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:v0.7.0 vip
      /kube-vip manifest pod
      --interface eth0
      --address 192.168.1.100  # YOUR CONTROL PLANE VIP
      --controlplane
      --arp
      --leaderElection
      > /etc/kubernetes/manifests/kube-vip.yaml
```

#### 4.3 Edit workers.yaml

Key customizations:

```yaml
spec:
  replicas: 2  # YOUR WORKER COUNT

  template:
    spec:
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: my-cluster-workers
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: my-cluster-workers
```

### Step 5: Deploy the Cluster

```bash
# Apply cluster manifests
kubectl apply -f my-cluster/cluster.yaml
kubectl apply -f my-cluster/control-plane.yaml
kubectl apply -f my-cluster/workers.yaml

# Watch cluster creation
watch kubectl get cluster,kubeadmcontrolplane,machinedeployment,machine,bmh
```

**Expected sequence:**
1. Cluster resources created (Cluster, KubeadmControlPlane, MachineDeployment)
2. Machines created by CAPI
3. Metal3 claims BareMetalHosts matching labels
4. Ironic provisions OS images to BMHs
5. Nodes boot, network configured via networkData
6. Kubeadm init/join runs
7. ClusterResourceSet deploys Cilium
8. Cluster becomes Ready

### Step 6: Access the Cluster

```bash
# Get kubeconfig
clusterctl get kubeconfig my-cluster > my-cluster-kubeconfig.yaml

# Set context
export KUBECONFIG=my-cluster-kubeconfig.yaml

# Verify nodes
kubectl get nodes -o wide

# Verify Cilium
kubectl -n kube-system get pods -l k8s-app=cilium

# Check Cilium status
cilium status

# For HA clusters, verify kube-vip
kubectl -n kube-system get pods -l component=kube-vip
```

### Step 7: Verify Networking

```bash
# Check pod networking
kubectl run test-pod --image=nginx --rm -it -- /bin/sh
# Should be able to curl other pods

# Verify DNS
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default

# For BGP setups, verify peering
cilium bgp peers
cilium bgp routes advertised ipv4 unicast
```

## Common Patterns

### Adding Workers to Existing Cluster

```bash
# Scale MachineDeployment
kubectl patch machinedeployment my-cluster-workers \
  --type merge \
  -p '{"spec":{"replicas":3}}'

# BEFORE scaling: Ensure you have additional BMHs labeled
kubectl label bmh my-host-5 cluster.x-k8s.io/cluster-name=my-cluster
kubectl label bmh my-host-5 cluster.x-k8s.io/role=worker

# Patch BMH with networkData
kubectl patch bmh my-host-5 --type merge -p '{
  "spec": {
    "networkData": {
      "name": "my-cluster-node5-network",
      "namespace": "default"
    }
  }
}'
```

### Cluster with BGP

After cluster is running, apply BGP configuration:

```bash
kubectl apply -f my-cluster/bgp/cilium-bgp-cluster-config.yaml
kubectl apply -f my-cluster/bgp/cilium-bgp-peer-config.yaml
kubectl apply -f my-cluster/bgp/cilium-bgp-advertisement.yaml

# Verify BGP sessions
cilium bgp peers
```

See [templates/examples/bgp-simple.yaml](templates/examples/bgp-simple.yaml) for BGP configuration examples.

### Updating Cluster Configuration

CAPI clusters are declarative - update the manifests and apply:

```bash
# Example: Add another control plane node
kubectl patch kubeadmcontrolplane my-cluster-control-plane \
  --type merge \
  -p '{"spec":{"replicas":3}}'

# BEFORE scaling: Label additional BMH
kubectl label bmh my-host-3 cluster.x-k8s.io/cluster-name=my-cluster
kubectl label bmh my-host-3 cluster.x-k8s.io/role=control-plane
```

## Troubleshooting

### Cluster Not Provisioning

```bash
# Check cluster status
kubectl describe cluster my-cluster

# Check control plane status
kubectl describe kubeadmcontrolplane my-cluster-control-plane

# Check machines
kubectl get machines -o wide
kubectl describe machine <machine-name>

# Check BMH status
kubectl get bmh -o wide
kubectl describe bmh <bmh-name>

# Check Metal3 provisioning
kubectl -n metal3 logs -l app=metal3-baremetal-operator
```

### Nodes Not Joining

```bash
# Get BMH console logs (if available)
kubectl get bmh <bmh-name> -o json | jq -r '.status.provisioning.state'

# Check if networkData was applied
# SSH to node (if accessible) and check network config
ip addr
ip route
cat /etc/resolv.conf

# Check cloud-init logs on node
sudo journalctl -u cloud-init
sudo cat /var/log/cloud-init.log
```

### CNI Not Deploying

```bash
# Check ClusterResourceSet
kubectl describe clusterresourceset my-cluster-cilium

# Check if resources were applied to workload cluster
export KUBECONFIG=my-cluster-kubeconfig.yaml
kubectl -n kube-system get pods -l k8s-app=cilium

# Check Cilium pod logs
kubectl -n kube-system logs -l k8s-app=cilium --tail=100
```

### BGP Not Peering

```bash
# Check BGP configuration applied
kubectl get ciliumbgpclusterconfig,ciliumbgppeerconfig,ciliumbgpadvertisement

# Check Cilium BGP status
cilium bgp peers
cilium bgp routes

# Check Cilium logs for BGP errors
kubectl -n kube-system logs -l k8s-app=cilium | grep -i bgp

# Verify node labels match BGP policy selectors
kubectl get nodes --show-labels
```

## Best Practices

1. **Always configure networkData before CAPI claims BMH**
   - CAPI preserves networkData when claiming
   - Changing networkData after provisioning requires reprovisioning

2. **Use labels for BMH assignment**
   - Explicit cluster-name and role labels
   - Prevents accidental BMH assignment

3. **Test with single node first**
   - Deploy 1 control plane, verify it works
   - Then scale to HA

4. **Keep cluster configs in git**
   - Version control all YAML
   - Easy to recreate or update clusters

5. **Use ClusterResourceSet for bootstrap only**
   - CNI and essential components
   - Day-2 operations via GitOps (see [../docs/bootstrap-to-gitops.md](../docs/bootstrap-to-gitops.md))

6. **Set k8sServiceHost in Cilium**
   - Always point to control plane VIP
   - Prevents bootstrap issues

7. **Document your cluster configs**
   - README in each cluster directory
   - Note IP assignments, BMH mappings, special configs

## References

- [Architecture Decision Records](../adr/README.md) - Why these patterns were chosen
- [Bootstrap to GitOps](../docs/bootstrap-to-gitops.md) - Day-0 to Day-2 operations
- [Template Examples](templates/) - Working configuration examples
- [Cluster API Book](https://cluster-api.sigs.k8s.io/) - Upstream documentation
- [Metal3 Docs](https://metal3.io/documentation.html) - Metal3 project documentation
- [Cilium Documentation](https://docs.cilium.io/) - Cilium CNI and BGP
