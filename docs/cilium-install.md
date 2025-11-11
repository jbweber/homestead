# Cilium CNI Installation Pattern for Cluster API + Metal3

## Overview

This document describes the pattern for installing Cilium as the CNI (Container Network Interface) in clusters provisioned by Cluster API with Metal3. This approach uses **rendered manifests** applied via **ClusterResourceSet** for deterministic, GitOps-friendly CNI deployment.

## Architecture Decision

We use a **rendered manifest approach** rather than runtime Helm installation because:

- **Deterministic**: Exact manifests are known before deployment
- **No runtime dependencies**: No need for Helm, internet access, or chart repositories in the cluster
- **GitOps friendly**: All manifests are version controlled and auditable
- **Production appropriate**: Eliminates runtime variables and potential failures
- **Metal3 aligned**: Infrastructure-as-code approach matches bare metal philosophy

## Pattern Components

### 1. Cluster Configuration (No Default CNI)

Configure the KubeadmControlPlane to skip default CNI installation:

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: my-cluster-control-plane
  namespace: default
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      networking:
        podSubnet: "10.244.0.0/16"  # Adjust to your network design
    initConfiguration:
      skipPhases:
        - addon/kube-proxy  # Optional: Cilium can replace kube-proxy
    joinConfiguration:
      skipPhases:
        - addon/kube-proxy  # Optional
```

### 2. Manifest Generation (Local)

Use the Cilium CLI locally to generate rendered manifests:

```bash
# Install Cilium CLI if not already installed
# See: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/

# Generate Cilium manifests with desired configuration
cilium install \
  --version 1.14.5 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set tunnel=disabled \
  --set ipv4NativeRoutingCIDR=10.244.0.0/16 \
  --set autoDirectNodeRoutes=true \
  --dry-run > cilium-manifests.yaml
```

**Key Configuration Options for Metal3:**

- `ipam.mode=kubernetes`: Use Kubernetes for IP address management
- `kubeProxyReplacement=true`: Replace kube-proxy with Cilium's eBPF implementation
- `tunnel=disabled`: Use native routing for better bare metal performance
- `ipv4NativeRoutingCIDR`: Match your pod subnet for direct routing
- `autoDirectNodeRoutes=true`: Automatically configure node routes

**BGP Support for LoadBalancer Services:**

For bare metal environments requiring BGP for LoadBalancer IP advertisement, enable BGP support in the bootstrap:

```bash
# Generate Cilium manifests with BGP subsystem enabled
cilium install \
  --version 1.14.5 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set tunnel=disabled \
  --set ipv4NativeRoutingCIDR=10.244.0.0/16 \
  --set autoDirectNodeRoutes=true \
  --set bgpControlPlane.enabled=true \
  --set bgp.enabled=true \
  --set bgp.announce.loadbalancerIP=true \
  --dry-run > cilium-manifests.yaml
```

**Important**: This enables the BGP subsystem but does **not** configure BGP peering. The actual BGP peering policies (neighbors, ASNs, etc.) should be managed via GitOps tools like ArgoCD after the cluster is operational. This separation allows:

- **Bootstrap**: BGP capability installed and ready
- **Day-2 Operations**: BGP peering configuration managed through Git
- **Flexibility**: Different peering configs per environment/rack without cluster recreation

See the [Bootstrap to GitOps Pattern](./bootstrap-to-gitops-pattern.md) document for details on managing BGP peering policies via ArgoCD.

### 3. ConfigMap Creation

Package the rendered manifests into a ConfigMap:

```bash
kubectl create configmap cilium-cni-manifests \
  --from-file=cilium.yaml=cilium-manifests.yaml \
  --namespace default \
  --dry-run=client -o yaml > cilium-crs-configmap.yaml
```

### 4. ClusterResourceSet Definition

Create a ClusterResourceSet to automatically apply Cilium to matching clusters:

```yaml
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: cilium-cni-crs
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      cni: cilium
  resources:
  - name: cilium-cni-manifests
    kind: ConfigMap
  strategy: ApplyOnce  # Or "Reconcile" for continuous reconciliation
```

**Strategy Options:**

- **`ApplyOnce`** (default and recommended): Applies resources only once during cluster creation. After initial application, ClusterResourceSet stops managing these resources, allowing you to hand off management to other tools like ArgoCD or Flux. This is ideal for bootstrap scenarios.

- **`Reconcile`**: Continuously reconciles resources, overwriting any manual changes or updates made by other tools. Generally not recommended as it conflicts with GitOps workflows and day-2 operations tools.

### 5. Cluster Labeling

Label your Cluster resource to trigger the ClusterResourceSet:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
  namespace: default
  labels:
    cni: cilium  # This triggers the ClusterResourceSet
spec:
  # ... rest of cluster spec
```

## Deployment Workflow

### Initial Setup

```bash
# 1. Generate Cilium manifests using the documented script
# IMPORTANT: You MUST provide the API server endpoint (control plane VIP)
# See: homestead/capi/generate-cilium-manifests.sh
./generate-cilium-manifests.sh /path/to/environment-files/<cluster-name>/cilium <api-server-ip> [api-server-port]

# Example for capi-1 cluster (VIP: 10.250.250.29):
./generate-cilium-manifests.sh /home/jweber/projects/environment-files/capi-1/cilium 10.250.250.29

# The script generates manifests with our standard configuration:
# - k8sServiceHost/Port: Direct API server endpoint (CRITICAL for bootstrap)
# - Native routing (no tunnels) for bare metal performance
# - BGP control plane enabled for LoadBalancer support
# - Custom CNI bin path (/var/lib/cni/bin) for Fedora images
# - kube-proxy replacement with eBPF
# See script output for detailed explanation of all settings

# 2. Create ConfigMap definition
kubectl create configmap cilium-cni-manifests \
  --from-file=cilium.yaml=cilium-manifests.yaml \
  --dry-run=client -o yaml > cilium-crs-configmap.yaml

# 3. Commit to version control
git add cilium-manifests.yaml cilium-crs-configmap.yaml cilium-crs.yaml
git commit -m "Add Cilium CNI configuration"

# 4. Apply to management cluster
kubectl apply -f cilium-crs-configmap.yaml
kubectl apply -f cilium-crs.yaml
```

### Provisioning a New Cluster

**IMPORTANT**: Before creating the cluster, ensure BareMetalHost resources are ready:

```bash
# Pre-provisioning checklist:
# 1. Verify BMH manifests have correct labels
#    - cluster.x-k8s.io/cluster-name: <cluster-name>
#    - cluster.x-k8s.io/role: control-plane or worker
# 2. Verify BMHs have spec.online: true
# 3. Apply/reapply BMH manifests to ensure they're up to date
kubectl apply -f baremetalhosts.yaml

# 4. Verify BMHs are online and available
kubectl get bmh | grep <cluster-name>
# Should show STATE=available and ONLINE=true

# 5. Verify ClusterResourceSet exists in management cluster
kubectl get clusterresourceset cilium-cni-crs
```

**Create the Cluster:**

```bash
# 1. Create cluster with CNI label (cni: cilium triggers ClusterResourceSet)
kubectl apply -f <cluster-manifest>.yaml
# Ensure cluster manifest has:
#   metadata.labels.cni: cilium
#   kubeadmConfigSpec.initConfiguration.skipPhases: [addon/kube-proxy]
#   kubeadmConfigSpec.joinConfiguration.skipPhases: [addon/kube-proxy]

# 2. Verify ClusterResourceSet binding was created
kubectl get clusterresourcesetbinding <cluster-name>

# 3. Monitor cluster provisioning
kubectl get machines,bmh -l cluster.x-k8s.io/cluster-name=<cluster-name>

# 4. Once control plane is ready, verify Cilium installation
clusterctl get kubeconfig <cluster-name> > <cluster-name>.kubeconfig
cilium status --kubeconfig <cluster-name>.kubeconfig --wait

# 5. Run connectivity tests
cilium connectivity test --kubeconfig <cluster-name>.kubeconfig
```

## Verification and Operations

### Check Cilium Status

```bash
# Get kubeconfig for workload cluster
clusterctl get kubeconfig <cluster-name> > kubeconfig.yaml

# Check Cilium status
cilium status --kubeconfig kubeconfig.yaml --wait

# Verify all pods are running
kubectl --kubeconfig kubeconfig.yaml -n kube-system get pods -l k8s-app=cilium
```

### Connectivity Testing

```bash
# Run comprehensive connectivity test suite
cilium connectivity test --kubeconfig kubeconfig.yaml

# This tests:
# - Pod-to-pod communication
# - Pod-to-service communication
# - External connectivity
# - Network policies
# - And more...
```

### Debugging

```bash
# Collect comprehensive debug information
cilium sysdump --kubeconfig kubeconfig.yaml

# Monitor network traffic (requires Hubble)
cilium hubble observe --kubeconfig kubeconfig.yaml
```

## Updating Cilium Version

To update Cilium across your clusters:

```bash
# 1. Generate new manifests with updated version
cilium install \
  --version 1.15.0 \
  [same options as before] \
  --dry-run > cilium-manifests-v1.15.0.yaml

# 2. Review the diff
diff cilium-manifests.yaml cilium-manifests-v1.15.0.yaml

# 3. Update the ConfigMap
mv cilium-manifests-v1.15.0.yaml cilium-manifests.yaml
kubectl create configmap cilium-cni-manifests \
  --from-file=cilium.yaml=cilium-manifests.yaml \
  --dry-run=client -o yaml > cilium-crs-configmap.yaml

# 4. Commit and apply
git add cilium-manifests.yaml cilium-crs-configmap.yaml
git commit -m "Update Cilium to v1.15.0"
kubectl apply -f cilium-crs-configmap.yaml

# 5. For existing clusters, manually apply updates
# (ClusterResourceSet with ApplyOnce won't auto-update)
kubectl --kubeconfig workload.kubeconfig apply -f cilium-manifests.yaml
```

## Per-Cluster Customization

For different configurations per cluster (e.g., production vs. development):

```bash
# Generate different manifest sets
cilium install --dry-run [prod-options] > cilium-prod-manifests.yaml
cilium install --dry-run [dev-options] > cilium-dev-manifests.yaml

# Create separate ConfigMaps
kubectl create configmap cilium-cni-prod --from-file=...
kubectl create configmap cilium-cni-dev --from-file=...

# Create separate ClusterResourceSets with different selectors
# Production CRS matches label: environment=production
# Development CRS matches label: environment=development
```

## Troubleshooting

### ClusterResourceSet Not Applying

```bash
# Check CRS status
kubectl get clusterresourceset cilium-cni-crs -o yaml

# Check if cluster has matching labels
kubectl get cluster <cluster-name> --show-labels

# Check CRS binding
kubectl get clusterresourcesetbinding -n <cluster-namespace>
```

### Cilium Pods Not Starting

```bash
# Check pod status and events
kubectl --kubeconfig workload.kubeconfig -n kube-system describe pods -l k8s-app=cilium

# Check logs
kubectl --kubeconfig workload.kubeconfig -n kube-system logs -l k8s-app=cilium

# Verify node readiness (nodes won't be ready until CNI is functional)
kubectl --kubeconfig workload.kubeconfig get nodes
```

### Init Container Timeout: "dial tcp 10.96.0.1:443: i/o timeout"

**Symptom**: Cilium pods stuck in `Init:0/6` state with config init container failing

**Error in logs**:
```
level=error msg="Unable to contact k8s api-server" subsys=cilium-dbg module=k8s-client
ipAddr=https://10.96.0.1:443 error="Get \"https://10.96.0.1:443/api/v1/namespaces/kube-system\":
dial tcp 10.96.0.1:443: i/o timeout"
```

**Root Cause**: When using `kubeProxyReplacement=true` without setting `k8sServiceHost` and `k8sServicePort`, Cilium tries to contact the Kubernetes API via the Service ClusterIP (10.96.0.1:443). This creates a chicken-and-egg problem:
- kube-proxy is skipped (Cilium replaces it)
- Service ClusterIP routing requires either kube-proxy or Cilium to be running
- Cilium can't start because it can't reach the API server
- Result: Bootstrap deadlock

**Solution**: Regenerate manifests with the API server endpoint:

```bash
# 1. Get the control plane VIP from your cluster manifest
grep -A 2 "controlPlaneEndpoint:" <cluster-manifest>.yaml

# 2. Regenerate Cilium manifests with the VIP address
cd homestead/capi
./generate-cilium-manifests.sh /path/to/environment-files/<cluster>/cilium <vip-address>

# Example:
./generate-cilium-manifests.sh /home/jweber/projects/environment-files/capi-1/cilium 10.250.250.29

# 3. Update ConfigMap in management cluster
kubectl create configmap cilium-cni-manifests \
  --from-file=cilium.yaml=cilium-manifests.yaml \
  --namespace default \
  --dry-run=client -o yaml > cilium-crs-configmap.yaml
kubectl apply -f cilium-crs-configmap.yaml

# 4. Apply updated manifests to existing cluster (if already provisioned)
clusterctl get kubeconfig <cluster-name> > cluster.kubeconfig
kubectl --kubeconfig cluster.kubeconfig apply -f cilium-manifests.yaml

# 5. Verify Cilium pods restart and become Running
kubectl --kubeconfig cluster.kubeconfig get pods -n kube-system -l k8s-app=cilium
```

**Verification**: Check that `KUBERNETES_SERVICE_HOST` is set to your VIP (not 10.96.0.1):
```bash
kubectl --kubeconfig cluster.kubeconfig get pod -n kube-system -l k8s-app=cilium -o yaml | \
  grep -A 2 "KUBERNETES_SERVICE_HOST"
```

### Network Connectivity Issues

```bash
# Run Cilium connectivity test
cilium connectivity test --kubeconfig workload.kubeconfig

# Check Cilium agent health
cilium status --kubeconfig workload.kubeconfig

# Verify pod CIDR configuration matches
kubectl --kubeconfig workload.kubeconfig cluster-info dump | grep -i cidr
```

## Production Recovery Patterns

### Stuck Machine Recovery (Without Cluster Deletion)

**Scenario**: A Machine is stuck in Provisioning phase and the node never joins the cluster, but the rest of the cluster is healthy.

**Solution**: Delete the stuck Machine, not the Cluster. CAPI's declarative model will automatically create a replacement.

```bash
# 1. Verify cluster health with existing nodes
clusterctl get kubeconfig <cluster-name> > cluster.kubeconfig
kubectl --kubeconfig cluster.kubeconfig get nodes
kubectl --kubeconfig cluster.kubeconfig get pods -n kube-system

# 2. Identify the stuck machine
kubectl get machines -l cluster.x-k8s.io/cluster-name=<cluster-name>
# Look for machines stuck in "Provisioning" phase with READY=Unknown

# 3. Delete ONLY the stuck machine (not the cluster)
kubectl delete machine <stuck-machine-name>

# 4. Monitor replacement creation
kubectl get machines -l cluster.x-k8s.io/cluster-name=<cluster-name> -w

# What happens:
# - KubeadmControlPlane controller sees: desired=3, current=2 (after deletion)
# - Automatically creates a NEW Machine to replace the deleted one
# - New Machine claims an available BareMetalHost
# - New node provisions and joins the cluster
# - Cluster reaches desired state without downtime
```

**Example Recovery**:
```bash
# Situation: capi-1-dwtmc stuck, master-2 and worker-1 healthy
$ kubectl delete machine capi-1-dwtmc
machine.cluster.x-k8s.io "capi-1-dwtmc" deleted

# Result: New machine created immediately
$ kubectl get machines -l cluster.x-k8s.io/cluster-name=capi-1
NAME                         PHASE          AGE
capi-1-729mh                 Provisioning   15s   # NEW replacement
capi-1-workers-6lsn5-mx8gs   Running        26m   # Existing worker
capi-1-zphzn                 Running        26m   # Existing control plane

# Cluster continued operating throughout recovery
```

**Key Benefits**:
- No cluster downtime
- Existing workloads unaffected
- Declarative reconciliation handles replacement
- Same pattern works for control plane and worker nodes

## References

- [Cilium Documentation](https://docs.cilium.io/)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)
- [ClusterResourceSet Documentation](https://cluster-api.sigs.k8s.io/tasks/experimental-features/cluster-resource-set.html)
- [Metal3 Documentation](https://metal3.io/)

## Advantages of This Pattern

✅ **Deterministic**: Know exactly what gets deployed  
✅ **Version Controlled**: All manifests in Git  
✅ **Auditable**: Easy to review changes in PRs  
✅ **No Runtime Dependencies**: Works in air-gapped environments  
✅ **Automated**: New clusters get CNI automatically via labels  
✅ **Testable**: Can validate manifests before deployment  
✅ **Metal3 Optimized**: Native routing, no tunnels, optimal for bare metal  
✅ **GitOps Ready**: Using `ApplyOnce` allows seamless handoff to ArgoCD/Flux for day-2 operations

## Trade-offs

⚠️ **Manual Updates**: Updating requires regenerating and applying manifests  
⚠️ **Large ConfigMaps**: Full Cilium manifests can be verbose  
⚠️ **Per-Cluster Variation**: Requires multiple ConfigMaps/CRS for different configs  

These trade-offs are acceptable for infrastructure-grade bare metal clusters where stability and predictability are paramount.

## BGP Configuration for Pod Network Advertisement

After cluster provisioning, you can configure Cilium's BGP control plane to advertise pod networks to your infrastructure routers. This is a **day-1 operation** performed after the cluster is running.

### Prerequisites

- Cilium installed with `bgpControlPlane.enabled=true` (set during manifest generation)
- Infrastructure router supporting BGP (e.g., FRR on UDM, Cisco, Juniper)
- Network connectivity between cluster nodes and BGP peer

### Configuration Pattern

Cilium BGP uses three CRDs (v2 API):

1. **CiliumBGPClusterConfig** - Defines BGP instances and peers
2. **CiliumBGPPeerConfig** - Configures peer settings (timers, multihop, etc.)
3. **CiliumBGPAdvertisement** - Specifies what to advertise (PodCIDR, LoadBalancer IPs, etc.)

### Example Configuration

**Step 1: Create BGP Configuration Files**

```yaml
# cilium-bgp-cluster-config.yaml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux  # Apply to all nodes
  bgpInstances:
  - name: "65010"
    localASN: 65010
    peers:
    - name: "peer-65001"
      peerASN: 65001
      peerAddress: 192.168.254.1  # Your router IP
      peerConfigRef:
        name: "peer-65001"
```

```yaml
# cilium-bgp-peer-config.yaml
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: peer-65001
spec:
  timers:
    holdTimeSeconds: 90
    keepAliveTimeSeconds: 30
  ebgpMultihop: 10
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
  - afi: ipv4
    safi: unicast
    advertisements:
      matchLabels:
        advertise: "bgp"
```

```yaml
# cilium-bgp-advertisement.yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: pod-cidr-advertisement
  labels:
    advertise: "bgp"  # Must match peer config selector
spec:
  advertisements:
  - advertisementType: "PodCIDR"
```

**Step 2: Apply Configuration to Cluster**

```bash
# Get cluster kubeconfig
clusterctl get kubeconfig <cluster-name> > cluster.kubeconfig

# Apply BGP configuration
kubectl --kubeconfig cluster.kubeconfig apply -f cilium-bgp-cluster-config.yaml
kubectl --kubeconfig cluster.kubeconfig apply -f cilium-bgp-peer-config.yaml
kubectl --kubeconfig cluster.kubeconfig apply -f cilium-bgp-advertisement.yaml
```

**Step 3: Configure Router**

Example FRR configuration using peer-groups (recommended):

```
router bgp 65001
  bgp router-id 192.168.254.1

  # Define peer-group for cluster nodes (simplifies management)
  neighbor CAPI1 peer-group
  neighbor CAPI1 remote-as 65010
  neighbor CAPI1 ebgp-multihop 255
  neighbor CAPI1 update-source 192.168.254.1
  neighbor CAPI1 soft-reconfiguration inbound
  neighbor CAPI1 prefix-list RECEIVE_ONLY in
  neighbor CAPI1 route-map BLOCK_OUT out

  # Add cluster nodes to peer-group (one line per node)
  neighbor 10.250.250.20 peer-group CAPI1
  neighbor 10.250.250.21 peer-group CAPI1
  neighbor 10.250.250.22 peer-group CAPI1
  neighbor 10.250.250.23 peer-group CAPI1

!
# Prefix-list to allow all inbound routes
ip prefix-list RECEIVE_ONLY seq 5 permit 0.0.0.0/0 le 32

# Route-map to block outbound advertisements (receive-only mode)
route-map BLOCK_OUT deny 10
```

**Benefits of peer-groups:**
- All shared settings defined once
- Adding workers: just `neighbor <new-ip> peer-group CAPI1`
- Update all cluster nodes simultaneously by modifying peer-group

**Step 4: Verify BGP Sessions**

```bash
# Check Cilium BGP status in cluster
kubectl --kubeconfig cluster.kubeconfig logs -n kube-system -l k8s-app=cilium | grep -i bgp

# Expected output includes:
# level=info msg="Registering BGP instance" instance=65010
# level=info msg="Adding peer" peer=peer-65001
# level=info msg="Peer Up" State=BGP_FSM_OPENCONFIRM

# Check router BGP status
ssh <router> vtysh -c 'show bgp summary'
ssh <router> vtysh -c 'show bgp ipv4 unicast'
```

### Key Design Points

- **Node Selector**: Using `kubernetes.io/os: linux` automatically includes all nodes (control plane + workers)
- **Dynamic Scaling**: As you add workers, BGP is automatically configured on new nodes
- **Per-Node PodCIDR**: Each node advertises its own /24 PodCIDR with itself as next-hop (native routing)
- **Peer-Groups**: Simplify router config by defining shared settings once (reduces config from 24 lines to 4)
- **Unnumbered BGP**: Not yet supported by Cilium ([Issue #22132](https://github.com/cilium/cilium/issues/22132)) - must use explicit IP addresses for peering

### Troubleshooting BGP

**Check BGP peering status:**
```bash
# View Cilium BGP resources
kubectl --kubeconfig cluster.kubeconfig get ciliumbgpclusterconfig
kubectl --kubeconfig cluster.kubeconfig get ciliumbgppeerconfig
kubectl --kubeconfig cluster.kubeconfig get ciliumbgpadvertisement

# Check BGP peering from Cilium pods
kubectl --kubeconfig cluster.kubeconfig exec -n kube-system ds/cilium -- cilium bgp peers

# Check advertised routes from all nodes
kubectl --kubeconfig cluster.kubeconfig exec -n kube-system ds/cilium -- cilium bgp routes advertised ipv4 unicast

# Check for BGP errors in Cilium logs
kubectl --kubeconfig cluster.kubeconfig logs -n kube-system -l k8s-app=cilium | grep -i "bgp\|error"

# Expected successful output in logs:
# level=info msg="Registering BGP instance" instance=<ASN>
# level=info msg="Adding peer" peer=<peer-name>
# level=info msg="Peer Up" State=BGP_FSM_OPENCONFIRM
```

**Common Issues:**

- **Peer not establishing**: Check network connectivity, firewall rules (TCP port 179)
- **Routes not appearing**: Verify advertisement labels match peer config selector
- **eBGP multihop**: Ensure ebgpMultihop is set if router is not directly connected

## Transitioning to Day-2 Operations

This pattern is designed for **day-0 bootstrapping**. Once your cluster is operational, you can hand off ongoing management to GitOps tools like ArgoCD or Flux. The `ApplyOnce` strategy ensures ClusterResourceSet won't interfere with day-2 operations.

See the companion document [Bootstrap to GitOps Pattern](./bootstrap-to-gitops-pattern.md) for details on transitioning from initial cluster provisioning to ongoing GitOps management.