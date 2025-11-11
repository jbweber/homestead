# Setting Network Config on BareMetalHost Outside of CAPI

## Status: ✅ Recommended Approach

**Validated**: 2025-11-10 - Successfully tested with simple (single interface) and complex (bond+VLAN) configurations.

**This is the RECOMMENDED approach for all CAPI deployments.**

## The Approach
Pre-create `BareMetalHost` resources with network configuration already set, then let CAPI claim and manage them for cluster provisioning.

## How It Works
1. Create BMH with `spec.networkData` pointing to your OpenStack network_data.json secret
2. Leave `spec.userData` empty (CAPI will populate this)
3. CAPI's Metal3 provider finds available BMHs and claims them
4. When claiming, CAPI **preserves** existing `spec.networkData`
5. CAPI sets `spec.userData` from KubeadmBootstrapProvider
6. Provisioning proceeds with your network config + CAPI's bootstrap data

## Example
```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-0
  labels:
    cluster.x-k8s.io/cluster-name: my-cluster  # REQUIRED for CAPI to find it
    cluster.x-k8s.io/role: worker              # REQUIRED for role-based selection
spec:
  online: true
  bootMACAddress: "00:11:22:33:44:55"
  bmc:
    address: ipmi://192.168.1.10
    credentialsName: worker-0-bmc-secret
  networkData:
    name: worker-0-network  # Your pre-created network config
    namespace: default
  # userData left empty - CAPI will set this
```

## Advantages
- ✅ Use the network config format you already tested and know works
- ✅ Separation of concerns (network vs. cluster lifecycle)
- ✅ No need to learn Metal3DataTemplate
- ✅ Easy to update network config independently
- ✅ Works with existing BMH inventory

## Potential Issues

### 1. BMH Must Be in `available` State
- CAPI only claims BMHs with `status.provisioning.state: available`
- If BMH is `provisioning`, `provisioned`, or has a `consumerRef`, CAPI will skip it
- **Fix**: Ensure BMH is fresh or properly deprovisioned before CAPI deployment

### 2. Selection/Matching
- Need enough available BMHs for your cluster size
- Use labels and `hostSelector` in Metal3MachineTemplate to control which BMH goes where
- Without selectors, CAPI claims first available BMH (may not be deterministic)

### 3. Scaling Considerations
- For MachineDeployment scaling up, you need additional available BMHs with network config
- Can't dynamically scale beyond pre-created BMH inventory
- **Fix**: Pre-create more BMHs than initially needed, or create them on-demand

### 4. Network Config Updates
- Updating network config on an already-provisioned BMH requires reprovisioning
- CAPI won't automatically trigger reprovisioning on network config changes
- **Fix**: Delete Machine to trigger deprovisioning, update BMH network, let CAPI re-claim

### 5. ConsumerRef Management
- If BMH has `spec.consumerRef` set (from previous use), CAPI won't claim it
- Must manually clear `consumerRef` to make BMH available again
- **Fix**: `kubectl patch bmh <name> --type=merge -p '{"spec":{"consumerRef":null}}'`

## Workflow
```bash
# 1. Create network config secrets
kubectl apply -f network-secrets.yaml

# 2. Create or update BMHs with network config and labels
kubectl apply -f bmh-inventory.yaml

# 3. Label BMHs for CAPI selection (REQUIRED!)
kubectl label bmh master-1 master-2 master-3 \
  cluster.x-k8s.io/cluster-name=my-cluster \
  cluster.x-k8s.io/role=control-plane

kubectl label bmh worker-1 worker-2 \
  cluster.x-k8s.io/cluster-name=my-cluster \
  cluster.x-k8s.io/role=worker

# 4. Verify BMHs are available with correct labels
kubectl get bmh -L cluster.x-k8s.io/cluster-name,cluster.x-k8s.io/role
# Should show provisioning.state: available with labels set

# 5. Deploy CAPI cluster (will claim labeled BMHs)
kubectl apply -f my-cluster-manifest.yaml

# 6. Watch CAPI claim and provision
kubectl get bmh,machines -w
# Should see consumerRef set and state change to provisioning
```

## When This Approach Works Best
- You have a static inventory of hardware
- Network config is complex/custom and you've already tested it
- You want network management separate from cluster lifecycle
- You're comfortable managing BMH resources directly

## When to Use Metal3DataTemplate Instead
- Dynamic IP allocation from pools
- Template-based network config across many machines
- Fully declarative cluster creation (everything in one apply)
- Don't want to manage individual BMH resources