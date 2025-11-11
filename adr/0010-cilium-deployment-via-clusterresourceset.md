---
status: accepted
date: 2025-11-10
---

# Cilium Deployment via ClusterResourceSet

## Context and Problem Statement

Cluster API provisions bare metal Kubernetes clusters, but CNI installation is required before pods can schedule and the cluster becomes fully functional. The CNI must be deployed early in the cluster lifecycle, ideally automatically as part of the provisioning workflow. How should Cilium CNI be deployed to CAPI-provisioned clusters to ensure consistent installation and minimal manual intervention?

## Decision Drivers

* Automation - CNI deployed automatically during cluster provisioning
* Consistency - Same CNI configuration across all clusters
* CAPI integration - Leverage CAPI mechanisms for cluster resources
* Bootstrap timing - CNI available before attempting to schedule workload pods
* Version control - CNI manifests tracked in git
* Cluster-specific config - Support per-cluster Cilium configuration
* Operational simplicity - Minimize manual steps

## Considered Options

* **Option 1**: ClusterResourceSet with rendered Helm manifests
* **Option 2**: Manual kubectl apply after cluster creation
* **Option 3**: Helm install via automation (Ansible/scripts)
* **Option 4**: Flux/ArgoCD GitOps deployment
* **Option 5**: Cluster API addons (experimental)

## Decision Outcome

Chosen option: **"ClusterResourceSet with rendered Helm manifests"**, because it provides automated CNI deployment integrated with CAPI cluster lifecycle, ensures CNI is installed before cluster is considered ready, and allows cluster-specific configuration while keeping manifests in version control.

The implementation uses:
- Helm template to render Cilium manifests with desired configuration
- Rendered YAML stored in ConfigMap
- ClusterResourceSet references ConfigMap
- CAPI automatically applies resources to matching clusters
- Cilium deployed during cluster bootstrap (before workload scheduling)

### Consequences

* Good, because CNI deployed automatically as part of cluster provisioning
* Good, because CAPI-native approach (no external tools required)
* Good, because ensures CNI available before cluster fully operational
* Good, because consistent CNI configuration across clusters
* Good, because rendered manifests in version control (git)
* Good, because cluster-specific configuration via separate ClusterResourceSets
* Good, because no manual kubectl/helm commands needed
* Bad, because rendered manifests verbose (full YAML in ConfigMap)
* Bad, because Helm chart updates require re-rendering manifests
* Bad, because ClusterResourceSet applies once (updates require deletion/recreation)
* Neutral, because appropriate for bootstrap CNI (not for day-2 operations)

### Confirmation

This decision is validated through operational experience:
1. Cilium automatically deployed to new clusters during provisioning
2. CNI available before attempting to schedule workload pods
3. Multiple clusters provisioned with consistent Cilium configuration
4. Cluster-specific Cilium config (different BGP settings) working correctly
5. No manual intervention required for CNI installation
6. Reprovisioning validated - Cilium deployed correctly on cluster recreation

## Pros and Cons of the Options

### Option 1: ClusterResourceSet with rendered Helm manifests

* Good, because CAPI-native automation
* Good, because CNI deployed during cluster bootstrap
* Good, because no external tools required
* Good, because manifests in version control
* Good, because cluster-specific configuration supported
* Good, because consistent across clusters
* Bad, because verbose rendered manifests
* Bad, because updates require re-rendering
* Bad, because ClusterResourceSet one-time application
* Neutral, because appropriate for bootstrap, not day-2 updates

### Option 2: Manual kubectl apply after cluster creation

* Good, because simple concept
* Good, because direct control over installation
* Good, because uses upstream Cilium manifests directly
* Bad, because manual intervention required
* Bad, because error-prone (easy to forget)
* Bad, because inconsistent timing (when is cluster ready?)
* Bad, because doesn't scale (manual per cluster)
* Bad, because not integrated with CAPI workflow

### Option 3: Helm install via automation (Ansible/scripts)

* Good, because uses Helm directly (easier updates)
* Good, because can be automated via scripts
* Good, because Helm values in version control
* Bad, because requires external automation (Ansible, bash scripts)
* Bad, because not CAPI-integrated
* Bad, because additional tooling dependency
* Bad, because timing coordination needed (when is API server ready?)
* Neutral, because automation possible but not CAPI-native

### Option 4: Flux/ArgoCD GitOps deployment

* Good, because GitOps workflow
* Good, because handles updates automatically
* Good, because sophisticated reconciliation
* Good, because manages ongoing lifecycle
* Bad, because chicken-and-egg problem (need CNI before Flux/ArgoCD can run)
* Bad, because adds significant complexity for bootstrap
* Bad, because Flux/ArgoCD themselves need to be installed
* Neutral, because excellent for day-2 operations but not bootstrap CNI

### Option 5: Cluster API addons (experimental)

* Good, because designed for this use case
* Good, because CAPI-native
* Bad, because experimental/alpha status
* Bad, because limited adoption
* Bad, because uncertain future
* Bad, because not production-ready
* Neutral, because may be future solution but not ready today

## More Information

This decision was made based on requirements for:
- Automated CNI deployment during cluster provisioning
- CAPI-integrated workflow without external dependencies
- Consistent CNI configuration across clusters
- Version-controlled manifests
- Support for cluster-specific configurations

ClusterResourceSet deployment workflow:

1. **Render Helm manifests**:
```bash
helm template cilium cilium/cilium \
  --namespace kube-system \
  --version 1.15.0 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=CLUSTER_VIP \
  --set k8sServicePort=6443 \
  > cilium-manifests.yaml
```

2. **Create ConfigMap with manifests**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cilium-crs-configmap
  namespace: default
data:
  cilium-install.yaml: |
    # Rendered Cilium manifests here
```

3. **Create ClusterResourceSet**:
```yaml
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: cilium-crs
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      cni: cilium
  resources:
  - kind: ConfigMap
    name: cilium-crs-configmap
```

4. **Label cluster for CNI deployment**:
```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
  labels:
    cni: cilium  # Matches ClusterResourceSet selector
```

Critical configuration - k8sServiceHost/Port:
- **Must** set to control plane VIP (not individual node IP)
- **Reason**: Avoids bootstrap chicken-and-egg problem
- **Problem**: Cilium needs API server access before CNI fully operational
- **Solution**: Direct Cilium to use VIP (kube-vip already running as static pod)

Cluster-specific configuration:
- Create separate ClusterResourceSet for cluster-specific settings
- Example: Different BGP configuration per cluster
- Use cluster labels to target specific ClusterResourceSets
- Allows baseline Cilium + cluster-specific overrides

Update workflow:
- ClusterResourceSet applies resources once at cluster creation
- Updates to ConfigMap don't automatically propagate
- For CNI updates: Delete and recreate ClusterResourceSet (risky)
- Better: Use GitOps (Flux/ArgoCD) for day-2 CNI management

When to reconsider:
- Cluster API addons mature and become production-ready
- Need frequent CNI updates (day-2 operations)
- GitOps workflow established (use Flux/ArgoCD for ongoing management)

Bootstrap vs Day-2 operations:
- **ClusterResourceSet**: Perfect for bootstrap (one-time installation)
- **GitOps (Flux/ArgoCD)**: Better for day-2 (ongoing updates and lifecycle)
- **Pattern**: Use ClusterResourceSet for initial CNI, migrate to GitOps for management

Related decisions:
- ADR-0008: CNI Selection (Cilium chosen)
- ADR-0009: BGP Routing with Cilium (BGP config deployed via ClusterResourceSet)
- ADR-0006: kube-vip for Control Plane HA (Cilium must use VIP in k8sServiceHost)
- Future: Bootstrap to GitOps transition (see docs/bootstrap-to-gitops.md)
