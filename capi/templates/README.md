# Cluster Templates

This directory contains working template configurations for creating Kubernetes clusters with Cluster API and Metal3.

## Directory Structure

```
templates/
├── simple/          # Single control plane cluster (development/testing)
├── ha/              # HA cluster (3 control planes + workers)
└── examples/        # Real-world configuration examples
```

## Usage

1. **Copy a template directory** as starting point for your cluster:
   ```bash
   cp -r templates/simple my-cluster
   cd my-cluster
   ```

2. **Edit the YAMLs** with your cluster-specific values:
   - Search and replace `CLUSTER_NAME` with your cluster name
   - Update IP addresses, CIDRs, and network configuration
   - Adjust node counts (replicas)
   - Configure kube-vip VIP address
   - Set OS image URL

3. **Prepare BareMetalHosts**:
   - Create network configuration secrets
   - Label BMHs for your cluster
   - Update BMHs with networkData references

4. **Deploy**:
   ```bash
   kubectl apply -f cluster.yaml
   kubectl apply -f control-plane.yaml
   kubectl apply -f workers.yaml
   kubectl apply -f cni/
   ```

See [../CLUSTER_TEMPLATE.md](../CLUSTER_TEMPLATE.md) for detailed step-by-step instructions.

## Template Descriptions

### simple/

**Use for:** Development, testing, learning

**Configuration:**
- 1 control plane node
- 2 worker nodes
- Single interface networking
- Static IP configuration
- Cilium CNI with ClusterResourceSet
- No BGP (can be added later)

**Files:**
- `cluster.yaml` - Cluster and Metal3Cluster resources
- `control-plane.yaml` - KubeadmControlPlane with single replica
- `workers.yaml` - MachineDeployment for worker nodes
- `cni/cilium-crs.yaml` - ClusterResourceSet for Cilium CNI
- `network-example.yaml` - Example network configuration secret

### ha/

**Use for:** Production, high-availability requirements

**Configuration:**
- 3 control plane nodes (HA with kube-vip)
- 3+ worker nodes
- kube-vip for control plane VIP
- Static IP configuration
- Cilium CNI with ClusterResourceSet
- Optional BGP configuration included

**Files:**
- `cluster.yaml` - Cluster and Metal3Cluster with control plane endpoint
- `control-plane.yaml` - KubeadmControlPlane with 3 replicas and kube-vip
- `workers.yaml` - MachineDeployment for worker nodes
- `cni/cilium-crs.yaml` - ClusterResourceSet for Cilium CNI
- `bgp/` - Optional BGP configuration files
- `network-example.yaml` - Example network configuration secret

### examples/

**Real-world configuration examples:**

- `network-simple.yaml` - Basic static IP configuration
- `network-complex.yaml` - Bond + VLAN configuration
- `network-multi-interface.yaml` - Multiple network interfaces
- `bgp-simple.yaml` - Basic BGP peering configuration
- `bgp-production.yaml` - Production BGP with redundant peers
- `clusterresourceset-patterns.yaml` - Various CRS patterns

## Customization Checklist

When adapting a template, ensure you update:

### Cluster-wide Settings
- [ ] Cluster name (everywhere)
- [ ] Pod CIDR (podSubnet)
- [ ] Service CIDR (services.cidrBlocks)
- [ ] Control plane endpoint (VIP for HA, node IP for simple)
- [ ] OS image URL

### Per-Node Settings
- [ ] Network configuration (IP, gateway, DNS)
- [ ] MAC addresses (if using MAC matching)
- [ ] BMH labels (cluster-name, role)
- [ ] networkData secret names

### CNI Configuration
- [ ] k8sServiceHost (must match control plane endpoint)
- [ ] k8sServicePort (typically 6443)
- [ ] ipv4NativeRoutingCIDR (must match pod CIDR)
- [ ] BGP configuration (if applicable)

### kube-vip Configuration (HA only)
- [ ] VIP address in preKubeadmCommands
- [ ] Interface name (typically eth0)
- [ ] VIP matches cluster.spec.controlPlaneEndpoint

## Quick Start Examples

### Simple Cluster

```bash
# 1. Copy template
cp -r templates/simple dev-cluster
cd dev-cluster

# 2. Find and replace cluster name
find . -type f -exec sed -i 's/CLUSTER_NAME/dev-cluster/g' {} \;

# 3. Edit cluster.yaml - update CIDRs and control plane endpoint
vim cluster.yaml

# 4. Create network configs for each node
kubectl create secret generic dev-cluster-cp1-network \
  --from-file=networkData=network-cp1.json

kubectl create secret generic dev-cluster-worker1-network \
  --from-file=networkData=network-worker1.json

# 5. Label and update BMHs
kubectl label bmh node-01 cluster.x-k8s.io/cluster-name=dev-cluster
kubectl label bmh node-01 cluster.x-k8s.io/role=control-plane
kubectl patch bmh node-01 --type merge -p '{
  "spec": {"networkData": {"name": "dev-cluster-cp1-network"}}
}'

# 6. Deploy
kubectl apply -f cluster.yaml
kubectl apply -f control-plane.yaml
kubectl apply -f workers.yaml
kubectl apply -f cni/
```

### HA Cluster

```bash
# 1. Copy template
cp -r templates/ha prod-cluster
cd prod-cluster

# 2. Find and replace cluster name
find . -type f -exec sed -i 's/CLUSTER_NAME/prod-cluster/g' {} \;

# 3. Edit cluster.yaml - set control plane VIP
vim cluster.yaml
# Update spec.controlPlaneEndpoint.host to your VIP

# 4. Edit control-plane.yaml - set VIP in kube-vip config
vim control-plane.yaml
# Update --address in preKubeadmCommands to match VIP

# 5. Create network configs and label BMHs for 3 control planes + workers
# (repeat for each node)

# 6. Deploy
kubectl apply -f cluster.yaml
kubectl apply -f control-plane.yaml
kubectl apply -f workers.yaml
kubectl apply -f cni/

# 7. Optional: Deploy BGP after cluster is running
kubectl apply -f bgp/
```

## Tips

1. **Start small, then scale:** Deploy with minimal replicas first, verify it works, then scale up

2. **Test networkData separately:** Before deploying cluster, verify network config works by applying to a test BMH

3. **Use version control:** Keep your cluster configs in git for easy tracking and rollback

4. **Document your choices:** Add a README to your cluster directory explaining IP assignments, special configurations, etc.

5. **ClusterResourceSet selectors:** Use unique labels for each cluster's CRS to avoid conflicts

6. **Image consistency:** Ensure all nodes use compatible OS images (same base image + version)

## Common Modifications

### Change Node Counts

**Control planes (HA only):**
```yaml
# In control-plane.yaml
spec:
  replicas: 5  # Must be odd number for etcd quorum
```

**Workers:**
```yaml
# In workers.yaml
spec:
  replicas: 10  # Any number
```

### Add BGP to Simple Cluster

1. Copy BGP configs from `ha/bgp/` or `examples/bgp-simple.yaml`
2. Update AS numbers and peer IPs for your environment
3. Apply after cluster is running:
   ```bash
   kubectl apply -f bgp/
   ```

### Use Different CNI

1. Don't apply the Cilium ClusterResourceSet
2. Manually deploy your CNI to the workload cluster after it's created
3. Or create a custom ClusterResourceSet for your CNI

### Complex Networking

See `examples/network-complex.yaml` for bond + VLAN configurations. Key points:

- Define bond in `links` section
- Add VLAN interfaces referencing bond
- Configure networks on VLAN interfaces
- Ensure MAC addresses match your hardware

## Troubleshooting

**BMH not being claimed:**
- Check labels match cluster name and role
- Verify BMH is in `available` state
- Check networkData secret exists and is referenced

**Control plane not forming:**
- For HA: Verify VIP is consistent across cluster.yaml and control-plane.yaml
- Check kube-vip interface name matches actual interface
- Ensure VIP is not already in use on network

**Cilium not deploying:**
- Verify ClusterResourceSet selector matches cluster labels
- Check k8sServiceHost points to correct control plane endpoint
- Look at ClusterResourceSet status: `kubectl describe clusterresourceset <name>`

**Nodes not joining:**
- Check networkData was applied (ssh to node, check `ip addr`)
- Verify DNS is configured correctly in networkData
- Check kubeadm logs on node: `journalctl -u kubelet`

## References

- [Main Template Guide](../CLUSTER_TEMPLATE.md)
- [Architecture Decision Records](../../adr/README.md)
- [Cluster API Documentation](https://cluster-api.sigs.k8s.io/)
- [Metal3 Documentation](https://metal3.io/)
