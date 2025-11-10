# Cluster API Installation and Cluster Deployment

This directory contains scripts for installing Cluster API (CAPI) with the Metal3 infrastructure provider and deploying Kubernetes clusters on bare metal hosts.

## Overview

Cluster API provides declarative, Kubernetes-style APIs for cluster creation, configuration, and management. With the Metal3 provider, you can deploy Kubernetes clusters on bare metal infrastructure using BareMetalHost resources.

## Prerequisites

Before running these scripts, ensure you have completed the Metal3 installation:

1. ✅ Kubernetes management cluster running (`metal3/01-install-k8s-single-node.sh`)
2. ✅ cert-manager installed (`metal3/02-install-cert-manager.sh`)
3. ✅ Ironic deployed (`metal3/03-install-ironic-operator.sh` and `04-deploy-ironic.sh`)
4. ✅ Bare Metal Operator installed (`metal3/05-install-bmo.sh`)
5. ✅ BareMetalHost resources created and in "available" state

Verify prerequisites with:
```bash
kubectl get nodes
kubectl get -n cert-manager deployments
kubectl get -n baremetal-operator-system deployments
kubectl get baremetalhosts -A
```

## Installation Scripts

Run these scripts in order to install Cluster API:

### 01-install-clusterctl.sh

Installs the `clusterctl` CLI tool for managing Cluster API providers.

```bash
./01-install-clusterctl.sh
```

**What it does:**
- Downloads latest stable clusterctl binary
- Installs to `~/.local/bin/clusterctl`
- Verifies installation
- Idempotent: safe to re-run

**After running:**
```bash
clusterctl version
```

---

### 02-install-capi-core.sh

Installs Cluster API core components.

```bash
./02-install-capi-core.sh
```

**What it does:**
- Installs CAPI core controller (v1.11.3)
- Installs Kubeadm bootstrap provider (v1.11.3)
- Installs Kubeadm control-plane provider (v1.11.3)
- Waits for all deployments to become ready

**Namespaces created:**
- `capi-system` - Core Cluster API controller
- `capi-kubeadm-bootstrap-system` - Bootstrap provider
- `capi-kubeadm-control-plane-system` - Control plane provider

---

### 03-install-metal3-provider.sh

Installs the Metal3 infrastructure provider and IPAM provider for bare metal clusters.

```bash
./03-install-metal3-provider.sh
```

**What it does:**
- Installs CAPM3 infrastructure provider (v1.11.1)
- Installs Metal3 IPAM (IP Address Manager) provider
- Integrates with existing BMO/Ironic installation
- Waits for CAPM3 and IPAM controllers to become ready

**Namespaces created:**
- `capm3-system` - Metal3 infrastructure provider
- `metal3-ipam-system` - Metal3 IP Address Manager

---

### 04-verify-installation.sh

Verifies that all Cluster API components are installed and ready.

```bash
./04-verify-installation.sh
```

**What it checks:**
- clusterctl installation
- All required namespaces exist
- All provider controllers are running
- Metal3 integration (BMO, BareMetalHost CRD)
- cert-manager status
- Available BareMetalHosts for cluster creation

---

## Deploying a Cluster

After installing Cluster API, you can deploy Kubernetes clusters using scripts 05 and 06.

### Step 1: Configure Environment Variables

Create a configuration file in `~/projects/environment-files/` with your cluster settings.

**Example: `~/projects/environment-files/my-cluster-variables.rc`**

```bash
#!/bin/bash
# Cluster Configuration
export CLUSTER_NAME="my-cluster"
export KUBERNETES_VERSION="v1.31.0"
export NAMESPACE="default"

# Network Configuration
export POD_CIDR="10.244.0.0/16"
export SERVICE_CIDR="10.96.0.0/12"

# Control Plane Configuration
export CONTROL_PLANE_MACHINE_COUNT="3"
export API_ENDPOINT_HOST="192.168.1.100"
export API_ENDPOINT_PORT="6443"

# Worker Configuration
export WORKER_MACHINE_COUNT="2"

# Image Configuration
export IMAGE_URL="http://192.168.1.10:8080/images/ubuntu-2204-kube-v1.31.0.qcow2"
export IMAGE_CHECKSUM="http://192.168.1.10:8080/images/ubuntu-2204-kube-v1.31.0.qcow2.sha256sum"
export IMAGE_CHECKSUM_TYPE="sha256"
export IMAGE_FORMAT="qcow2"

# BareMetalHost Selection
export CONTROL_PLANE_HOST_SELECTOR="node-role=control-plane"
export WORKER_HOST_SELECTOR="node-role=worker"
```

**For single-node clusters**, set:
```bash
export CONTROL_PLANE_MACHINE_COUNT="1"
export WORKER_MACHINE_COUNT="0"

# Allow workloads on control plane
export CTLPLANE_KUBEADM_EXTRA_CONFIG="
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: node.cluster.x-k8s.io/exclude-from-external-load-balancers=
    initConfiguration:
      nodeRegistration:
        taints: []
    joinConfiguration:
      nodeRegistration:
        taints: []
"
```

### Step 2: Generate Cluster Manifest

```bash
./05-generate-cluster-manifest.sh
```

**What it does:**
- Loads environment variables from `~/projects/environment-files/<cluster-name>-variables.rc`
- Validates all required variables are set
- Uses `clusterctl generate cluster` to create manifest
- Saves manifest to `~/projects/environment-files/<cluster-name>-manifest.yaml`
- Shows preview of resources to be created

### Step 3: Deploy Cluster

```bash
./06-deploy-cluster.sh
```

**What it does:**
- Applies the cluster manifest
- Monitors cluster creation progress
- Waits for control plane to initialize
- Retrieves kubeconfig when ready
- Saves kubeconfig to `~/projects/environment-files/<cluster-name>-kubeconfig.yaml`

**Access the new cluster:**
```bash
export KUBECONFIG=~/projects/environment-files/<cluster-name>-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

---

## Environment Variables Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `CLUSTER_NAME` | Name of the cluster | `my-cluster` |
| `KUBERNETES_VERSION` | Kubernetes version to deploy | `v1.31.0` |
| `POD_CIDR` | Pod network CIDR | `10.244.0.0/16` |
| `SERVICE_CIDR` | Service CIDR | `10.96.0.0/12` |
| `API_ENDPOINT_HOST` | Control plane API endpoint IP | `192.168.1.100` |
| `API_ENDPOINT_PORT` | API server port | `6443` |
| `CONTROL_PLANE_MACHINE_COUNT` | Number of control plane nodes | `3` |
| `WORKER_MACHINE_COUNT` | Number of worker nodes | `2` |
| `IMAGE_URL` | OS image URL | `http://host/image.qcow2` |
| `IMAGE_CHECKSUM` | Image checksum URL or value | `http://host/image.sha256sum` |
| `IMAGE_CHECKSUM_TYPE` | Checksum algorithm | `sha256` |
| `IMAGE_FORMAT` | Image format | `qcow2` or `raw` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NAMESPACE` | Kubernetes namespace for cluster resources | `default` |
| `CONTROL_PLANE_HOST_SELECTOR` | Label selector for control plane hosts (see note below) | - |
| `WORKER_HOST_SELECTOR` | Label selector for worker hosts | - |
| `CTLPLANE_KUBEADM_EXTRA_CONFIG` | Kubeadm extra configuration for control plane | - |
| `WORKERS_KUBEADM_EXTRA_CONFIG` | Kubeadm extra configuration for workers | - |

**Important Note on hostSelector**: When using `clusterctl generate`, the `CONTROL_PLANE_HOST_SELECTOR` variable may not be applied correctly to the generated manifest. You must manually add the `hostSelector` to the Metal3MachineTemplate spec and ensure your BareMetalHosts have matching labels. See the Troubleshooting section for details.

---

## Monitoring Cluster Deployment

### Watch cluster creation:
```bash
kubectl get cluster -n default -w
```

### Watch machines:
```bash
kubectl get machines -n default -w
```

### Watch BareMetalHost provisioning:
```bash
kubectl get baremetalhosts -A -w
```

### Check cluster status:
```bash
clusterctl describe cluster <cluster-name> -n default
```

### Quick health check:
```bash
./validate-health.sh
```

This runs a comprehensive check of all CAPI components, providers, and deployed clusters.

---

## Validating Your Installation

For comprehensive validation steps and troubleshooting, see [VALIDATION.md](VALIDATION.md).

The validation guide covers:
- Management cluster health checks
- CAPI core components verification
- Metal3 provider validation
- BareMetalHost resource checks
- Workload cluster status verification
- Common troubleshooting scenarios
- Health check commands and scripts

**Quick validation**:
```bash
./validate-health.sh
```

---

## Troubleshooting

For detailed troubleshooting guidance, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**Common Issues**:

- **Provider installation fails**: Check cert-manager is running and view provider logs
- **Cluster creation stalled**: Check BareMetalHost and Machine status
- **No available hosts**: Ensure hosts are in "available" state (not "ready")
- **hostSelector mismatch**: Add matching labels to BareMetalHost resources
- **Ironic stuck provisioning**: Rolling restart of Ironic clears in-memory database
- **DNS resolution errors**: Add DNS readiness wait in preKubeadmCommands

**Quick diagnostics**:
```bash
# Check all component health
./validate-health.sh

# Check cluster status
kubectl get cluster -n default
kubectl get machines -n default
kubectl get baremetalhosts -A

# View logs
kubectl logs -n capm3-system deployment/capm3-controller-manager -f
```

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions and step-by-step resolution procedures.

---

## Deleting a Cluster

To delete a cluster and release BareMetalHosts:

```bash
kubectl delete cluster <cluster-name> -n default
```

This will:
1. Delete the Cluster resource
2. Delete all Machine resources
3. Deprovision BareMetalHosts (return to "available" state)
4. Remove all cluster components

Monitor deletion:
```bash
kubectl get cluster -n default -w
kubectl get baremetalhosts -A -w
```

---

## Installing a CNI (Container Network Interface)

Kubernetes clusters require a CNI plugin for pod networking. There are several options for installing a CNI with CAPI clusters:

### Option 1: PostKubeadmCommands (Recommended for Simple Deployments)

Add CNI installation directly to the cluster manifest in `KubeadmControlPlane.spec.kubeadmConfigSpec.postKubeadmCommands`:

```yaml
spec:
  kubeadmConfigSpec:
    postKubeadmCommands:
      # Install Flannel CNI
      - kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
      # Or install Calico CNI
      # - kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml
```

**Pros:**
- Simple and straightforward
- Executes automatically during cluster creation
- No additional CAPI features required

**Cons:**
- Less declarative than ClusterResourceSet
- CNI manifest is external URL dependency

### Option 2: ClusterResourceSet (CAPI Native - Advanced)

Use CAPI's `ClusterResourceSet` feature to automatically apply CNI manifests to matching clusters:

```yaml
---
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: flannel-cni
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      cni: flannel
  resources:
    - name: flannel-cni-manifest
      kind: ConfigMap
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: flannel-cni-manifest
  namespace: default
data:
  flannel.yaml: |
    # Full Flannel CNI manifest content here
```

Then label your Cluster resource:
```yaml
metadata:
  labels:
    cni: flannel
```

**Pros:**
- Declarative and CAPI-native
- CNI manifest stored in management cluster (no external URL dependency)
- Reusable across multiple clusters
- Applied from management cluster (better for air-gapped environments)

**Cons:**
- Requires ClusterResourceSet feature (experimental in some CAPI versions)
- More complex setup
- Larger manifest files

**Enable ClusterResourceSet:**
```bash
# Add to clusterctl config or set environment variable
export EXP_CLUSTER_RESOURCE_SET=true
clusterctl init --infrastructure metal3
```

### Option 3: Files + PostKubeadmCommands

Embed the CNI manifest in the cluster manifest using the `files` field:

```yaml
spec:
  kubeadmConfigSpec:
    files:
      - path: /tmp/flannel.yaml
        owner: root:root
        permissions: '0644'
        content: |
          # Full CNI manifest content
    postKubeadmCommands:
      - kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /tmp/flannel.yaml
```

**Pros:**
- Self-contained (no external dependencies)
- Works in air-gapped environments

**Cons:**
- Makes manifest very large
- Less maintainable

### CNI Options

**Flannel** (Simplest):
- Lightweight VXLAN overlay network
- Minimal configuration required
- Good for single-node or small clusters
- Default pod CIDR: 10.244.0.0/16

**Calico** (Most Popular):
- Advanced network policies
- BGP or VXLAN modes
- Better for production and multi-node clusters
- Default pod CIDR: 192.168.0.0/16

**Cilium** (Advanced):
- eBPF-based for highest performance
- Advanced observability and security features
- More complex setup

### Verifying CNI Installation

After cluster deployment, check CNI pods are running:

```bash
# Get kubeconfig for new cluster
clusterctl get kubeconfig <cluster-name> > /tmp/cluster-kubeconfig.yaml

# Check CNI pods
kubectl --kubeconfig=/tmp/cluster-kubeconfig.yaml get pods -n kube-system -l app=flannel
# or for Calico
kubectl --kubeconfig=/tmp/cluster-kubeconfig.yaml get pods -n kube-system -l k8s-app=calico-node

# Verify nodes are Ready
kubectl --kubeconfig=/tmp/cluster-kubeconfig.yaml get nodes
```

---

## Upgrading Cluster API

To upgrade CAPI providers:

```bash
clusterctl upgrade plan
clusterctl upgrade apply --contract v1beta1
```

**Note:** Always backup your clusters before upgrading!

---

## Architecture

### Cluster API Components

Cluster API uses a management cluster to create and manage workload clusters. The management cluster runs several provider controllers:

**Core Providers** (v1.11.3):
- **capi-system**: Core Cluster API controller (manages Cluster, Machine resources)
- **capi-kubeadm-bootstrap-system**: Generates cloud-init for nodes using kubeadm
- **capi-kubeadm-control-plane-system**: Manages control plane lifecycle

**Infrastructure Provider** (v1.11.1):
- **capm3-system**: Metal3 infrastructure provider (bridges CAPI with bare metal)
- **metal3-ipam-system**: IP Address Management for Metal3

**Metal3 Components** (from metal3 scripts):
- **baremetal-operator-system**: Bare Metal Operator + Ironic service
- **cert-manager**: TLS certificates for webhooks

### Component Hierarchy

```
Management Cluster (metal3.example.com)
│
├── [Core] cert-manager
│   └── Provides TLS certificates for all webhooks
│
├── [Metal3] Ironic + Bare Metal Operator
│   └── Manages physical server provisioning
│
├── [CAPI Core] cluster-api controller
│   ├── Manages Cluster lifecycle
│   └── Creates Machine resources
│
├── [CAPI Bootstrap] kubeadm-bootstrap provider
│   └── Generates cloud-init configuration
│
├── [CAPI ControlPlane] kubeadm-control-plane provider
│   └── Manages KubeadmControlPlane resources
│
└── [CAPI Infrastructure] metal3-infrastructure provider
    ├── Creates Metal3Cluster (cluster infrastructure)
    ├── Creates Metal3Machine (node infrastructure)
    └── Selects BareMetalHosts for provisioning
```

### Resource Relationships

When you create a Cluster, CAPI creates a hierarchy of resources:

```
Cluster (user-defined)
├── Infrastructure → Metal3Cluster
│   └── API endpoint configuration
│
└── ControlPlane → KubeadmControlPlane
    └── MachineTemplate → Metal3MachineTemplate
        └── Machine (generated)
            ├── Infrastructure → Metal3Machine
            │   └── Selects → BareMetalHost
            │       └── Provisions via → Ironic
            │
            └── Bootstrap → KubeadmConfig
                └── Generates → Secret (cloud-init)
                    └── Used by → BareMetalHost
```

### Cluster Creation Flow

1. **User** creates `Cluster` resource with infrastructure and control plane references
2. **CAPI Core** reconciles Cluster, triggers infrastructure and control plane creation
3. **CAPM3** creates `Metal3Cluster` (infrastructure layer)
4. **Kubeadm ControlPlane Provider** creates `KubeadmControlPlane` resource
5. **KubeadmControlPlane** creates `Machine` resources based on replica count
6. **CAPM3** creates `Metal3Machine` for each Machine
7. **Metal3Machine** selects available `BareMetalHost` using hostSelector labels
8. **Kubeadm Bootstrap Provider** creates `KubeadmConfig` for each Machine
9. **KubeadmConfig** generates cloud-init Secret with kubeadm configuration
10. **CAPM3** updates BareMetalHost with image URL and userData secret reference
11. **BMO** (Bare Metal Operator) triggers Ironic to provision the host
12. **Ironic** provisions host via PXE/virtual media (boots image, writes disk)
13. **Host boots** from disk and cloud-init runs preKubeadmCommands
14. **Cloud-init** executes `kubeadm init` (control plane) or `kubeadm join` (workers)
15. **Machine** becomes Ready when node joins and reports Ready
16. **KubeadmControlPlane** reports Ready when all control plane machines are Ready
17. **Cluster** becomes Ready and kubeconfig is generated

### Provider Types

| Provider | Manages | Namespace |
|----------|---------|-----------|
| **Core** | Cluster, Machine, MachineSet, MachineDeployment | capi-system |
| **Bootstrap** | KubeadmConfig (cloud-init generation) | capi-kubeadm-bootstrap-system |
| **Control Plane** | KubeadmControlPlane (control plane lifecycle) | capi-kubeadm-control-plane-system |
| **Infrastructure** | Metal3Cluster, Metal3Machine (bare metal integration) | capm3-system |
| **IPAM** | IPPool, IPClaim, IPAddress | metal3-ipam-system |

### Validation Commands

```bash
# Check all CAPI controllers
kubectl get deployments -n capi-system
kubectl get deployments -n capi-kubeadm-bootstrap-system
kubectl get deployments -n capi-kubeadm-control-plane-system
kubectl get deployments -n capm3-system

# Check provider versions
kubectl get providers -A

# View cluster resources
kubectl get clusters -A
kubectl get machines -A
kubectl get baremetalhosts -A

# Detailed cluster description
clusterctl describe cluster <cluster-name> -n default
```

---

## References

- [Cluster API Documentation](../external/cluster-api/docs/)
- [CAPM3 Documentation](../external/cluster-api-provider-metal3/docs/)
- [Metal3 Documentation](../external/metal3-docs/)
- [Metal3 Installation Scripts](../metal3/)

---

## Files

### Scripts
- `01-install-clusterctl.sh` - Install clusterctl CLI
- `02-install-capi-core.sh` - Install CAPI core providers
- `03-install-metal3-provider.sh` - Install CAPM3 provider
- `04-verify-installation.sh` - Verify installation
- `05-generate-cluster-manifest.sh` - Generate cluster manifest
- `06-deploy-cluster.sh` - Deploy cluster
- `validate-health.sh` - Quick health check for all components

### Documentation
- `README.md` - This file (installation, usage, architecture)
- `VALIDATION.md` - Comprehensive validation procedures
- `TROUBLESHOOTING.md` - Detailed troubleshooting guide

### Environment Files (not in repo)
- `~/projects/environment-files/<cluster>-variables.rc` - Environment variables
- `~/projects/environment-files/<cluster>-manifest.yaml` - Generated cluster manifest
- `~/projects/environment-files/<cluster>-kubeconfig.yaml` - Cluster kubeconfig
