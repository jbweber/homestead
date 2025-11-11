# Bootstrap to GitOps: Day-0 to Day-2 Operations Pattern

## Overview

This document describes the complete lifecycle pattern for managing Cluster API + Metal3 clusters, from initial bootstrap (day-0) through ongoing operations (day-2). The pattern uses **ClusterResourceSet for bootstrapping** and **ArgoCD for ongoing management**, providing a clean separation of concerns.

## Philosophy

### Day-0: Bootstrap (ClusterResourceSet)
**Goal**: Get the cluster from "nothing" to "functional"

- Install critical infrastructure components (CNI, CSI, essential operators)
- Establish baseline functionality
- One-time setup that enables the cluster to run
- Uses `ApplyOnce` strategy - applies once and stops managing

### Day-2: Operations (ArgoCD/GitOps)
**Goal**: Manage the cluster through its operational lifecycle

- Ongoing configuration management
- Application deployment
- Updates and upgrades
- Policy enforcement
- Drift detection and correction
- Single source of truth in Git

## BGP Configuration Strategy

For bare metal environments requiring BGP for LoadBalancer services, we use a split approach:

### Bootstrap Phase: BGP Capability
- **What**: Enable Cilium BGP subsystem
- **Why**: Makes BGP functionality available from day-0
- **How**: Set `bgpControlPlane.enabled=true` in bootstrap manifest
- **Result**: BGP control plane running, but no peering sessions established

### GitOps Phase: BGP Configuration
- **What**: Apply CiliumBGPPeeringPolicy resources
- **Why**: Environment-specific peering configuration needs flexibility
- **How**: ArgoCD syncs BGP policies from Git repository
- **Result**: BGP sessions establish, LoadBalancer IPs advertised

### Rationale for This Split

**Why not include BGP peering in bootstrap?**
- BGP neighbors/ASNs vary by rack, datacenter, environment
- Peering policies are easier to update through Git than cluster recreation
- Testing BGP changes in staging before production
- Different clusters may need different BGP configurations
- Separation of infrastructure (BGP capability) from configuration (peering)

**Why not defer all BGP to GitOps?**
- BGP subsystem must be compiled into Cilium at install time
- Easier to have BGP ready than to add it later
- Cluster is "functional" immediately, "connected" shortly after

**The Result:**
- Cluster becomes operational in ~3 minutes (with CNI)
- External connectivity via BGP in ~5 minutes (after ArgoCD syncs)
- Total time to fully functional cluster: ~5 minutes
- BGP configuration remains flexible and manageable

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Management Cluster (Cluster API + Metal3)                   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ ClusterResourceSets (Day-0 Bootstrap)                │  │
│  │  • Cilium CNI                                         │  │
│  │  • CSI Drivers (optional)                            │  │
│  │  • ArgoCD Installation                               │  │
│  │  • Bootstrap Application                             │  │
│  │                                                        │  │
│  │  Strategy: ApplyOnce ← Hands off after bootstrap     │  │
│  └──────────────────────────────────────────────────────┘  │
│                             │                                │
│                             ▼                                │
│                    Provisions Cluster                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Workload Cluster                                             │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Bootstrap Phase (ClusterResourceSet applied)          │  │
│  │  ✓ Cilium CNI → Networking functional                │  │
│  │  ✓ ArgoCD → GitOps platform ready                    │  │
│  │  ✓ Bootstrap App → Points to Git repo                │  │
│  └──────────────────────────────────────────────────────┘  │
│                             │                                │
│                             ▼                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Day-2 Operations (ArgoCD manages)                     │  │
│  │  • Cilium configuration & updates                     │  │
│  │  • Cert-manager                                       │  │
│  │  • Ingress controllers                                │  │
│  │  • Monitoring stack                                   │  │
│  │  • Applications                                       │  │
│  │  • Security policies                                  │  │
│  │                                                        │  │
│  │  Source of Truth: Git Repository ←──────────────┐    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Implementation

### Step 1: Define Bootstrap Components

Create ClusterResourceSets for essential bootstrap components:

```yaml
---
# 1. Cilium CNI - Must be first (enables networking)
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: 01-cilium-cni
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      bootstrap: "true"
  resources:
  - name: cilium-cni-manifests
    kind: ConfigMap
  strategy: ApplyOnce
---
# 2. ArgoCD - GitOps platform
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: 02-argocd-install
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      bootstrap: "true"
  resources:
  - name: argocd-install-manifests
    kind: ConfigMap
  strategy: ApplyOnce
---
# 3. ArgoCD Bootstrap Application - Points to Git repo
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: 03-argocd-bootstrap-app
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      bootstrap: "true"
      environment: production  # Can vary by environment
  resources:
  - name: argocd-bootstrap-app-production
    kind: ConfigMap
  strategy: ApplyOnce
```

### Step 2: Prepare ConfigMaps

#### Cilium CNI ConfigMap

```bash
# Generate Cilium manifests with BGP subsystem enabled (but no peering configured)
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
  --dry-run > cilium-bootstrap.yaml

# Create ConfigMap
kubectl create configmap cilium-cni-manifests \
  --from-file=cilium.yaml=cilium-bootstrap.yaml \
  --namespace default \
  --dry-run=client -o yaml > cilium-crs-configmap.yaml
```

**Note on BGP Configuration**: The bootstrap includes BGP **capability** (the BGP subsystem is enabled), but does **not** include BGP peering policies. This allows the cluster to become functional immediately while deferring environment-specific BGP peering configuration to the GitOps phase. BGP peering policies will be applied by ArgoCD from Git after the cluster is operational.

#### ArgoCD Installation ConfigMap

```bash
# Download ArgoCD installation manifest
curl -L https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml > argocd-install.yaml

# Create namespace manifest
cat > argocd-namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
EOF

# Combine manifests
cat argocd-namespace.yaml argocd-install.yaml > argocd-complete.yaml

# Create ConfigMap
kubectl create configmap argocd-install-manifests \
  --from-file=argocd.yaml=argocd-complete.yaml \
  --namespace default \
  --dry-run=client -o yaml > argocd-install-configmap.yaml
```

#### ArgoCD Bootstrap Application ConfigMap

```bash
# Create bootstrap application manifest
cat > argocd-bootstrap-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-bootstrap
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/cluster-configs
    targetRevision: HEAD
    path: environments/production
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

# Create ConfigMap
kubectl create configmap argocd-bootstrap-app-production \
  --from-file=bootstrap-app.yaml=argocd-bootstrap-app.yaml \
  --namespace default \
  --dry-run=client -o yaml > argocd-bootstrap-configmap.yaml
```

### Step 3: Set Up Git Repository Structure

Your Git repository should follow this structure:

```
cluster-configs/
├── environments/
│   ├── production/
│   │   ├── app-of-apps.yaml           # Root application
│   │   └── applications/
│   │       ├── cilium.yaml
│   │       ├── cilium-bgp.yaml        # BGP peering policies
│   │       ├── cert-manager.yaml
│   │       ├── ingress-nginx.yaml
│   │       ├── monitoring.yaml
│   │       └── ...
│   ├── staging/
│   │   └── ...
│   └── development/
│       └── ...
├── base/
│   ├── cilium/
│   │   ├── values.yaml
│   │   └── kustomization.yaml
│   ├── cilium-bgp/
│   │   ├── production/
│   │   │   └── peering-policy.yaml
│   │   ├── staging/
│   │   │   └── peering-policy.yaml
│   │   └── common/
│   │       └── bgp-advertisements.yaml
│   ├── cert-manager/
│   │   └── ...
│   └── ...
└── README.md
```

#### Example: App-of-Apps Pattern

```yaml
# environments/production/app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-applications
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/cluster-configs
    targetRevision: HEAD
    path: environments/production/applications
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

#### Example: Cilium Application

```yaml
# environments/production/applications/cilium.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cilium
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://helm.cilium.io/
    chart: cilium
    targetRevision: 1.14.5
    helm:
      values: |
        ipam:
          mode: kubernetes
        kubeProxyReplacement: true
        tunnel: disabled
        ipv4NativeRoutingCIDR: 10.244.0.0/16
        autoDirectNodeRoutes: true
        # Additional day-2 features
        hubble:
          enabled: true
          relay:
            enabled: true
          ui:
            enabled: true
        prometheus:
          enabled: true
        operator:
          prometheus:
            enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
  ignoreDifferences:
  - group: ""
    kind: ConfigMap
    name: cilium-config
    jsonPointers:
    - /data/identity-allocation-mode  # Prevent oscillation
```

#### Example: Cert-Manager Application

```yaml
# environments/production/applications/cert-manager.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.13.0
    helm:
      values: |
        installCRDs: true
        prometheus:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

#### Example: Cilium BGP Configuration Application

```yaml
# environments/production/applications/cilium-bgp.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cilium-bgp-config
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/cluster-configs
    targetRevision: HEAD
    path: base/cilium-bgp/production
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

The BGP peering policy managed by this application:

```yaml
# base/cilium-bgp/production/peering-policy.yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: production-rack-peering
  namespace: kube-system
spec:
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/worker: ""
  virtualRouters:
  - localASN: 64512
    exportPodCIDR: false
    neighbors:
    # ToR switch 1
    - peerAddress: 192.168.1.1/32
      peerASN: 64501
      eBGPMultihopTTL: 1
      connectRetryTimeSeconds: 120
      holdTimeSeconds: 90
      keepAliveTimeSeconds: 30
    # ToR switch 2 (redundancy)
    - peerAddress: 192.168.1.2/32
      peerASN: 64501
      eBGPMultihopTTL: 1
      connectRetryTimeSeconds: 120
      holdTimeSeconds: 90
      keepAliveTimeSeconds: 30
    serviceSelector:
      matchExpressions:
      - key: bgp-advertise
        operator: In
        values:
        - external
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-loadbalancer-ips
  namespace: kube-system
spec:
  advertisements:
  - advertisementType: "Service"
    service:
      addresses:
      - LoadBalancerIP
    selector:
      matchExpressions:
      - key: bgp-advertise
        operator: In
        values:
        - external
```

**BGP Configuration Notes:**

- **Bootstrap Phase**: Cilium deployed with BGP subsystem enabled, but no peering configured
- **GitOps Phase**: BGP peering policies applied by ArgoCD from Git
- **Result**: Environment-specific BGP configuration managed separately from infrastructure bootstrap
- **Service Selection**: Only services with label `bgp-advertise: external` will have their LoadBalancer IPs advertised via BGP

### Step 4: Create and Label Cluster

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-cluster-01
  namespace: default
  labels:
    bootstrap: "true"        # Triggers all bootstrap CRS
    environment: production   # Triggers production-specific CRS
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 10.244.0.0/16
    services:
      cidrBlocks:
      - 10.96.0.0/12
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: prod-cluster-01-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: Metal3Cluster
    name: prod-cluster-01
---
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: prod-cluster-01-control-plane
  namespace: default
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      networking:
        podSubnet: "10.244.0.0/16"
    initConfiguration:
      skipPhases:
      - addon/kube-proxy  # Cilium replaces kube-proxy
    joinConfiguration:
      skipPhases:
      - addon/kube-proxy
  # ... rest of control plane spec
```

### Step 5: Apply Bootstrap Configuration

```bash
# Apply all bootstrap components to management cluster
kubectl apply -f cilium-crs-configmap.yaml
kubectl apply -f cilium-crs.yaml
kubectl apply -f argocd-install-configmap.yaml
kubectl apply -f argocd-install-crs.yaml
kubectl apply -f argocd-bootstrap-configmap.yaml
kubectl apply -f argocd-bootstrap-crs.yaml

# Create the cluster
kubectl apply -f prod-cluster-01.yaml
```

## The Bootstrap Sequence

When a new cluster is created, this sequence occurs automatically:

1. **Cluster API** provisions infrastructure via Metal3
2. **ClusterResourceSet `01-cilium-cni`** applies:
   - Cilium CNI manifests are deployed (with BGP subsystem enabled)
   - Networking becomes functional
   - Nodes transition to Ready state
   - BGP control plane is running, but no peers configured yet
3. **ClusterResourceSet `02-argocd-install`** applies:
   - ArgoCD namespace is created
   - ArgoCD components are deployed
   - ArgoCD server becomes ready
4. **ClusterResourceSet `03-argocd-bootstrap-app`** applies:
   - Bootstrap Application is created in ArgoCD
   - ArgoCD connects to Git repository
   - ArgoCD begins syncing cluster configuration
5. **ArgoCD takes over**:
   - Deploys all applications from Git
   - Applies BGP peering policies (CiliumBGPPeeringPolicy)
   - BGP sessions establish with ToR switches/routers
   - LoadBalancer IPs begin being advertised
   - Manages Cilium configuration (can update/enhance bootstrap config)
   - Deploys cert-manager, ingress, monitoring, etc.
   - Continuous reconciliation from Git

**Timeline:**
- T+0 to T+3 minutes: Bootstrap phase (cluster functional, no external BGP)
- T+3 to T+5 minutes: GitOps phase (BGP peering established, LoadBalancers externally accessible)
- T+5+ minutes: Ongoing operations (all applications deployed and managed)

## Verification and Monitoring

### Verify Bootstrap Phase

```bash
# Get kubeconfig for workload cluster
clusterctl get kubeconfig prod-cluster-01 > prod-cluster-01.kubeconfig
export KUBECONFIG=prod-cluster-01.kubeconfig

# Check that nodes are ready (confirms CNI is working)
kubectl get nodes

# Verify Cilium is running
cilium status --wait

# Check that BGP subsystem is enabled (but not yet peering)
kubectl -n kube-system get pods -l k8s-app=cilium
cilium bgp peers  # Should show no peers yet

# Check ArgoCD is installed
kubectl -n argocd get pods

# Verify ArgoCD is syncing
kubectl -n argocd get applications
```

### Monitor GitOps Phase

```bash
# Watch all ArgoCD applications
kubectl -n argocd get applications -w

# Check sync status
argocd app list

# View BGP application details
argocd app get cilium-bgp-config

# Verify BGP peering is established
cilium bgp peers
# Expected output should show established sessions with your ToR switches

# Check BGP routes being advertised
cilium bgp routes advertised ipv4 unicast

# Test LoadBalancer service gets advertised
kubectl create service loadbalancer test-lb --tcp=80:80
kubectl get svc test-lb  # Should get EXTERNAL-IP
# Verify the IP is advertised via BGP
cilium bgp routes advertised ipv4 unicast | grep <EXTERNAL-IP>

# Check for sync issues
argocd app sync cilium-bgp-config --dry-run
```

## Managing the Lifecycle

### Updating Bootstrap Components (New Clusters)

To change what gets bootstrapped on **new** clusters:

```bash
# 1. Update the manifest (e.g., new Cilium version)
cilium install --dry-run [new-options] > cilium-bootstrap-v2.yaml

# 2. Update ConfigMap
kubectl create configmap cilium-cni-manifests \
  --from-file=cilium.yaml=cilium-bootstrap-v2.yaml \
  --namespace default \
  --dry-run=client -o yaml > cilium-crs-configmap-v2.yaml

# 3. Apply to management cluster
kubectl apply -f cilium-crs-configmap-v2.yaml

# 4. New clusters will use updated bootstrap config
# Existing clusters are unaffected (ApplyOnce strategy)
```

### Updating Running Clusters (Day-2)

For **existing** clusters, updates happen through Git:

```bash
# 1. Update your Git repository
cd cluster-configs
vim environments/production/applications/cilium.yaml
# Change targetRevision: 1.15.0

# 2. Commit and push
git add environments/production/applications/cilium.yaml
git commit -m "Update Cilium to 1.15.0"
git push

# 3. ArgoCD automatically syncs (if automated)
# Or manually trigger:
argocd app sync cilium

# 4. Verify update
kubectl -n kube-system rollout status daemonset/cilium
cilium status
```

### Adding New Components

Add new components by creating ArgoCD Applications in Git:

```yaml
# environments/production/applications/prometheus.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 51.0.0
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Commit and push - ArgoCD will deploy automatically.

### Per-Environment Customization

Use different Git paths or overlays for different environments:

```yaml
# Production bootstrap app
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-bootstrap
spec:
  source:
    path: environments/production
  # ...

# Staging bootstrap app
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-bootstrap
spec:
  source:
    path: environments/staging
  # ...
```

Or use Kustomize overlays:

```
base/cilium/
├── kustomization.yaml
└── values.yaml

environments/production/overlays/cilium/
├── kustomization.yaml
└── values-production.yaml
```

## Troubleshooting

### Bootstrap Phase Issues

```bash
# Check ClusterResourceSet status
kubectl get clusterresourceset
kubectl describe clusterresourceset 01-cilium-cni

# Check if resources were applied
kubectl get clusterresourcesetbinding -n <cluster-namespace>

# Get workload cluster kubeconfig
clusterctl get kubeconfig <cluster-name> > kubeconfig.yaml

# Check if Cilium pods started
kubectl --kubeconfig kubeconfig.yaml -n kube-system get pods -l k8s-app=cilium

# Check if ArgoCD installed
kubectl --kubeconfig kubeconfig.yaml -n argocd get pods
```

### GitOps Phase Issues

```bash
# Check ArgoCD application status
kubectl -n argocd get applications
argocd app get <app-name>

# View sync errors
argocd app sync <app-name> --dry-run

# Check ArgoCD logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-application-controller

# Force sync
argocd app sync <app-name> --force

# Refresh application (re-compare Git vs cluster)
argocd app refresh <app-name>
```

### Cilium Not Updating via ArgoCD

If ArgoCD can't update Cilium (conflicts with bootstrap):

```bash
# Check for resource conflicts
kubectl -n kube-system get daemonset cilium -o yaml | grep annotations

# ArgoCD may need to take ownership
kubectl -n kube-system annotate daemonset cilium \
  argocd.argoproj.io/tracking-id=cilium:apps/DaemonSet:kube-system/cilium

# Or delete bootstrap Cilium and let ArgoCD recreate
# (Do this carefully in a maintenance window!)
kubectl --kubeconfig kubeconfig.yaml -n kube-system delete daemonset cilium
argocd app sync cilium
```

### BGP Peering Issues

```bash
# Check if BGP peering policy was applied
kubectl -n kube-system get ciliumbgppeeringpolicies
kubectl -n kube-system describe ciliumbgppeeringpolicy production-rack-peering

# View BGP peer status
cilium bgp peers

# Check for BGP-related events
kubectl -n kube-system get events --sort-by='.lastTimestamp' | grep -i bgp

# Verify node labels match peering policy selector
kubectl get nodes --show-labels

# Check Cilium logs for BGP errors
kubectl -n kube-system logs -l k8s-app=cilium | grep -i bgp

# Test with a LoadBalancer service
kubectl create service loadbalancer test-bgp --tcp=80:80
kubectl get svc test-bgp
# Should get an EXTERNAL-IP

# Verify routes are being advertised
cilium bgp routes advertised ipv4 unicast

# Check if ToR switches are receiving routes (from switch CLI)
# Example for Arista switches:
# show ip bgp summary
# show ip bgp neighbors <peer-ip> routes
```

## Best Practices

### Bootstrap Minimalism
- Keep bootstrap minimal - only essential components
- Everything else should be in Git/ArgoCD
- Bootstrap = "cluster can run"
- Day-2 = "cluster does useful work"
- Enable BGP subsystem in bootstrap, configure peering in GitOps

### BGP Configuration Management
- **Bootstrap**: Enable BGP capability only (`bgpControlPlane.enabled=true`)
- **GitOps**: Manage all BGP peering policies via ArgoCD
- Use service selectors to control which LoadBalancers are advertised
- Keep peering policies environment-specific (different Git paths)
- Test BGP configuration in staging before applying to production
- Document your ASN assignments and IP ranges

### Git Repository Organization
- Separate environments (production, staging, dev)
- Use App-of-Apps pattern for organization
- Store values files in Git, not inline in Applications
- Use Kustomize or Helm for templating

### Security
- Use separate ArgoCD projects per team/namespace
- Implement RBAC for ArgoCD access
- Use sealed secrets or external secret operators
- Enable ArgoCD SSO authentication

### Monitoring
- Deploy ArgoCD notifications for sync failures
- Monitor ClusterResourceSet application with Prometheus
- Set up alerts for ArgoCD out-of-sync applications
- Use ArgoCD ApplicationSet for multi-cluster management

### Disaster Recovery
- Keep bootstrap manifests in version control
- Document the bootstrap process
- Test cluster recreation regularly
- Have runbooks for common failure scenarios

## Advanced Patterns

### Progressive Delivery

Use ArgoCD with Argo Rollouts for progressive delivery:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  source:
    repoURL: https://github.com/your-org/my-app
    path: manifests
  syncPolicy:
    automated:
      prune: false  # Don't auto-prune during rollout
```

### Multi-Cluster Management

Use ArgoCD ApplicationSets to manage multiple clusters:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-configs
spec:
  generators:
  - list:
      elements:
      - cluster: prod-cluster-01
        environment: production
      - cluster: prod-cluster-02
        environment: production
  template:
    metadata:
      name: '{{cluster}}-config'
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/cluster-configs
        path: 'environments/{{environment}}'
      destination:
        name: '{{cluster}}'
```

### Sealed Secrets for Bootstrap

If you need secrets during bootstrap:

```bash
# Create sealed secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Add to ClusterResourceSet ConfigMap
kubectl create configmap bootstrap-secrets \
  --from-file=secrets.yaml=sealed-secret.yaml
```

## Summary

This pattern provides:

- ✅ **Clean Separation**: Bootstrap vs. Operations
- ✅ **Automation**: New clusters come up fully configured
- ✅ **GitOps**: Single source of truth for cluster config
- ✅ **Flexibility**: Easy per-environment customization
- ✅ **Scalability**: Manage many clusters with ApplicationSets
- ✅ **Reliability**: Declarative, auditable, reproducible

**The flow:**
1. Cluster API + ClusterResourceSet → Cluster becomes functional
2. ArgoCD bootstrapped → GitOps platform ready
3. Git repository → ArgoCD manages everything
4. Updates via Git commits → ArgoCD syncs automatically

This pattern scales from single clusters to large fleets while maintaining operational simplicity and reliability.