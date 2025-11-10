# Cluster API Validation Guide

This guide provides comprehensive steps to validate the Cluster API installation and deployed clusters.

## Prerequisites

Set the correct kubeconfig for the management cluster:

```bash
export KUBECONFIG=~/projects/environment-files/kubeconfig-metal3.yaml
```

---

## 1. Management Cluster Validation

### 1.1 Check Management Cluster Node

```bash
kubectl get nodes
```

**Expected Output**:
```
NAME                 STATUS   ROLES           AGE     VERSION
metal3.example.com   Ready    control-plane   Xh      v1.34.1
```

**What to verify**:
- Status is `Ready`
- Role includes `control-plane`
- Kubernetes version matches expected (v1.34.1)

---

### 1.2 Check Management Cluster Health

```bash
kubectl get pods -A | grep -E '(NAMESPACE|Running)' | head -20
```

**What to verify**:
- All system pods are in `Running` state
- No pods in `CrashLoopBackOff` or `Error` state

---

## 2. Cluster API Core Components

### 2.1 CAPI Core Controller

```bash
kubectl get deployments -n capi-system
```

**Expected Output**:
```
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
capi-controller-manager   1/1     1            1           XXm
```

**What to verify**:
- Deployment is `1/1` READY
- AVAILABLE is `1`

**Check pods**:
```bash
kubectl get pods -n capi-system
```

**Check logs** (if issues):
```bash
kubectl logs -n capi-system deployment/capi-controller-manager -f
```

---

### 2.2 Kubeadm Bootstrap Provider

```bash
kubectl get deployments -n capi-kubeadm-bootstrap-system
```

**Expected Output**:
```
NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
capi-kubeadm-bootstrap-controller-manager 1/1     1            1           XXm
```

---

### 2.3 Kubeadm Control Plane Provider

```bash
kubectl get deployments -n capi-kubeadm-control-plane-system
```

**Expected Output**:
```
NAME                                              READY   UP-TO-DATE   AVAILABLE   AGE
capi-kubeadm-control-plane-controller-manager     1/1     1            1           XXm
```

---

## 3. Metal3 Infrastructure Provider

### 3.1 CAPM3 Controller

```bash
kubectl get deployments -n capm3-system
```

**Expected Output**:
```
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
capm3-controller-manager   1/1     1            1           XXm
```

**Check logs**:
```bash
kubectl logs -n capm3-system deployment/capm3-controller-manager -f
```

---

### 3.2 Metal3 IPAM Provider

```bash
kubectl get deployments -n metal3-ipam-system
```

**Expected Output**:
```
NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
metal3-ipam-controller-manager    1/1     1            1           XXm
```

---

### 3.3 Bare Metal Operator

```bash
kubectl get deployments -n baremetal-operator-system
```

**Expected Output**:
```
NAME                                    READY   UP-TO-DATE   AVAILABLE   AGE
baremetal-operator-controller-manager   1/1     1            1           XXm
ironic-service                          1/1     1            1           XXm
```

**What to verify**:
- Both `baremetal-operator-controller-manager` and `ironic-service` are ready

---

## 4. Provider Versions

### 4.1 Check All Installed Providers

```bash
kubectl get providers -A
```

**Expected Output**:
```
NAMESPACE                           NAME                    TYPE                    PROVIDER       VERSION   INSTALLED UPGRADE AVAILABLE
capi-kubeadm-bootstrap-system       bootstrap-kubeadm       BootstrapProvider       kubeadm        v1.11.3   True
capi-kubeadm-control-plane-system   control-plane-kubeadm   ControlPlaneProvider    kubeadm        v1.11.3   True
capm3-system                        infrastructure-metal3   InfrastructureProvider  metal3         v1.11.1   True
capi-system                         cluster-api             CoreProvider            cluster-api    v1.11.3   True
```

**What to verify**:
- All providers show `INSTALLED: True`
- Versions match expected (CAPI v1.11.3, CAPM3 v1.11.1)

---

### 4.2 Check Provider Details with clusterctl

```bash
clusterctl version
```

**Expected Output**:
```
clusterctl version: &version.Info{Major:"1", Minor:"11", GitVersion:"v1.11.x"}
```

---

## 5. BareMetalHost Resources

### 5.1 List All BareMetalHosts

```bash
kubectl get baremetalhosts -A
```

**Expected Output**:
```
NAMESPACE   NAME    STATE         CONSUMER        ONLINE   ERROR   AGE
default     super   provisioned   super-ntzwt     true             XXh
```

**Possible States**:
- `available` - Ready to be provisioned by a cluster
- `provisioned` - Currently assigned to a cluster
- `provisioning` - Being provisioned
- `deprovisioning` - Being deprovisioned
- `inspecting` - Hardware inspection in progress
- `ready` - Previously provisioned, needs deprovisioning to become available

---

### 5.2 Detailed BareMetalHost Information

```bash
kubectl get baremetalhosts -A -o wide
```

**For specific host details**:
```bash
kubectl describe baremetalhost super -n default
```

**What to verify**:
- `Online: true` - Host is powered on
- `Provisioning State` matches expected
- No errors in status
- `Consumer` shows which Machine is using it (if provisioned)
- Hardware details (CPU, RAM, NIC) are detected

---

## 6. Workload Cluster Validation

### 6.1 List All Clusters

```bash
kubectl get clusters -A
```

**Expected Output**:
```
NAMESPACE   NAME    CLUSTERCLASS   AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE   VERSION
default     super                  True        1            1              1               0           0             0              Provisioned   XXm   v1.34.1
```

**Phases**:
- `Pending` - Cluster creation started
- `Provisioning` - Infrastructure being created
- `Provisioned` - Infrastructure created, waiting for cluster to be ready
- `Ready` - Cluster fully operational (control plane + CNI installed)
- `Deleting` - Cluster being deleted

**What to verify**:
- `AVAILABLE: True` means cluster API endpoint is reachable
- `CP DESIRED` = `CP AVAILABLE` = `CP UP-TO-DATE` for control plane
- `W DESIRED` = `W AVAILABLE` = `W UP-TO-DATE` for workers (0 for single-node)

---

### 6.2 Detailed Cluster Status

```bash
clusterctl describe cluster super -n default
```

**Expected Output**:
```
NAME                                           REPLICAS  AVAILABLE  READY  UP TO DATE  STATUS           REASON            SINCE  MESSAGE
Cluster/super                                  1/1       1          1      1           Available: True  Available         Xm
├─ClusterInfrastructure - Metal3Cluster/super                                          Ready: True      NoReasonReported  Xm
└─ControlPlane - KubeadmControlPlane/super     1/1       1          1      1
  └─Machine/super-xxxxx                        1         1          1      1           Ready: True      NodeReady         Xm
```

**What to verify**:
- Cluster shows `Available: True`
- ClusterInfrastructure shows `Ready: True`
- ControlPlane replicas match (1/1 for single-node)
- Machine shows `Ready: True` and `NodeReady`

**If Machine shows NOT ready**, check the message for details:
```
* NodeHealthy:
* Node.Ready: container runtime network not ready: NetworkPluginNotReady
  message:Network plugin returns error: no CNI configuration file in /etc/cni/net.d
```

This indicates CNI needs to be installed.

---

### 6.3 Check Machines

```bash
kubectl get machines -n default
```

**Expected Output**:
```
NAME          CLUSTER   NODE NAME   READY   AVAILABLE   UP-TO-DATE   PHASE     AGE   VERSION
super-xxxxx   super     super       True    True        True         Running   XXm   v1.34.1
```

**What to verify**:
- `READY: True` (requires CNI installed on workload cluster)
- `AVAILABLE: True`
- `PHASE: Running`
- NODE NAME matches expected hostname

---

### 6.4 Check KubeadmControlPlane

```bash
kubectl get kubeadmcontrolplane -n default
```

**Expected Output**:
```
NAME    CLUSTER   AVAILABLE   DESIRED   CURRENT   READY   AVAILABLE   UP-TO-DATE   INITIALIZED   AGE   VERSION
super   super     True        1         1         1       1           1            true          XXm   v1.34.1
```

**What to verify**:
- `AVAILABLE: True`
- `INITIALIZED: true`
- `READY` count matches `DESIRED`

---

### 6.5 Check Metal3 Infrastructure

```bash
kubectl get metal3cluster -n default
```

**Expected Output**:
```
NAME    CLUSTER   READY   AGE
super   super     true    XXm
```

```bash
kubectl get metal3machine -n default
```

**Expected Output**:
```
NAME          CLUSTER   STATE         READY   MACHINE       AGE
super-xxxxx   super     provisioned   true    super-xxxxx   XXm
```

---

## 7. Workload Cluster Access

### 7.1 Retrieve Kubeconfig

The kubeconfig is typically saved during deployment, but you can retrieve it manually:

```bash
clusterctl get kubeconfig super -n default > ~/projects/environment-files/super-kubeconfig.yaml
```

---

### 7.2 Access Workload Cluster

```bash
export KUBECONFIG=~/projects/environment-files/super-kubeconfig.yaml
kubectl get nodes
```

**Expected Output (after CNI installed)**:
```
NAME    STATUS   ROLES           AGE   VERSION
super   Ready    control-plane   XXm   v1.34.1
```

**Without CNI, will show**:
```
NAME    STATUS     ROLES           AGE   VERSION
super   NotReady   control-plane   XXm   v1.34.1
```

---

### 7.3 Check Workload Cluster Pods

```bash
kubectl get pods -A
```

**Expected Output (before CNI)**:
```
NAMESPACE     NAME                            READY   STATUS    RESTARTS   AGE
kube-system   coredns-xxxxx                   0/1     Pending   0          XXm
kube-system   etcd-super                      1/1     Running   0          XXm
kube-system   kube-apiserver-super            1/1     Running   0          XXm
kube-system   kube-controller-manager-super   1/1     Running   0          XXm
kube-system   kube-proxy-xxxxx                1/1     Running   0          XXm
kube-system   kube-scheduler-super            1/1     Running   0          XXm
```

**What to verify**:
- Control plane components are `Running`
- CoreDNS is `Pending` until CNI is installed

---

## 8. Certificate Manager Integration

```bash
export KUBECONFIG=~/projects/environment-files/kubeconfig-metal3.yaml
kubectl get pods -n cert-manager
```

**Expected Output**:
```
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-xxxxx                        1/1     Running   0          XXh
cert-manager-cainjector-xxxxx             1/1     Running   0          XXh
cert-manager-webhook-xxxxx                1/1     Running   0          XXh
```

**What to verify**:
- All three cert-manager pods are `Running`
- READY shows `1/1`

---

## 9. Validation and Debugging Commands

For detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### 9.1 Check Events

**Management cluster events**:
```bash
kubectl get events -n default --sort-by='.lastTimestamp' | tail -20
```

**Cluster-specific events**:
```bash
kubectl get events -n default --field-selector involvedObject.name=<cluster-name> --sort-by='.lastTimestamp'
```

---

### 9.2 Check Controller Logs

```bash
# CAPI Core
kubectl logs -n capi-system deployment/capi-controller-manager -f

# Metal3 Infrastructure Provider
kubectl logs -n capm3-system deployment/capm3-controller-manager -f

# Bare Metal Operator
kubectl logs -n baremetal-operator-system deployment/baremetal-operator-controller-manager -f

# Kubeadm Bootstrap
kubectl logs -n capi-kubeadm-bootstrap-system deployment/capi-kubeadm-bootstrap-controller-manager -f

# Kubeadm Control Plane
kubectl logs -n capi-kubeadm-control-plane-system deployment/capi-kubeadm-control-plane-controller-manager -f

# Ironic
kubectl logs -n baremetal-operator-system deployment/ironic-service -f
```

---

### 9.3 Check Machine Bootstrap Data

The bootstrap data (cloud-init) is stored as a Secret:

```bash
# List bootstrap secrets
kubectl get secrets -n default | grep bootstrap

# View cloud-init configuration
kubectl get secret <machine-name> -n default -o jsonpath='{.data.value}' | base64 -d
```

---

### 9.4 Quick Validation Scenarios

**Cluster stuck in "Provisioning"**:
```bash
kubectl get baremetalhosts -A
kubectl get machines -n default -o wide
clusterctl describe cluster <cluster-name> -n default
```

**Control plane not initializing**:
```bash
kubectl get kubeadmcontrolplane -n default
kubectl get machines -n default -o wide
kubectl logs -n capi-kubeadm-control-plane-system deployment/capi-kubeadm-control-plane-controller-manager --tail=50
```

**Machine shows "NotReady"**:
```bash
# Check if CNI is installed
clusterctl describe cluster <cluster-name> -n default

# Install CNI if missing (see README.md)
```

**Kubeconfig not available**:
```bash
# Check requirements
kubectl get cluster <cluster-name> -n default
kubectl get kubeadmcontrolplane -n default

# Retrieve manually
clusterctl get kubeconfig <cluster-name> -n default > <cluster>-kubeconfig.yaml
```

For detailed troubleshooting procedures, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## 11. Health Check Summary Script

Create a quick health check script to verify all components:

```bash
#!/bin/bash
set -euo pipefail

export KUBECONFIG=~/projects/environment-files/kubeconfig-metal3.yaml

echo "=== Management Cluster ==="
kubectl get nodes

echo -e "\n=== CAPI Controllers ==="
kubectl get deployments -n capi-system
kubectl get deployments -n capi-kubeadm-bootstrap-system
kubectl get deployments -n capi-kubeadm-control-plane-system

echo -e "\n=== Metal3 Controllers ==="
kubectl get deployments -n capm3-system
kubectl get deployments -n metal3-ipam-system
kubectl get deployments -n baremetal-operator-system

echo -e "\n=== Providers ==="
kubectl get providers -A

echo -e "\n=== BareMetalHosts ==="
kubectl get baremetalhosts -A

echo -e "\n=== Clusters ==="
kubectl get clusters -A

echo -e "\n=== Machines ==="
kubectl get machines -A

echo -e "\n=== Detailed Cluster Status ==="
kubectl get clusters -n default -o name | while read cluster; do
  cluster_name=$(echo $cluster | cut -d'/' -f2)
  echo "Cluster: $cluster_name"
  clusterctl describe cluster "$cluster_name" -n default
done

echo -e "\n=== Health Check Complete ==="
```

Save as `homestead/capi/validate-health.sh` and run:
```bash
chmod +x homestead/capi/validate-health.sh
./homestead/capi/validate-health.sh
```

---

## 12. Validation Checklist

Use this checklist to validate a complete CAPI installation:

### Installation Validation
- [ ] Management cluster node is Ready
- [ ] CAPI core controller running (capi-system)
- [ ] Kubeadm bootstrap provider running (capi-kubeadm-bootstrap-system)
- [ ] Kubeadm control-plane provider running (capi-kubeadm-control-plane-system)
- [ ] CAPM3 controller running (capm3-system)
- [ ] Metal3 IPAM controller running (metal3-ipam-system)
- [ ] Bare Metal Operator running (baremetal-operator-system)
- [ ] Ironic service running (baremetal-operator-system)
- [ ] cert-manager running (cert-manager)
- [ ] All providers show INSTALLED: True

### Cluster Deployment Validation
- [ ] Cluster resource created
- [ ] Cluster shows AVAILABLE: True
- [ ] BareMetalHost assigned to cluster (CONSUMER field populated)
- [ ] BareMetalHost state is "provisioned"
- [ ] BareMetalHost ONLINE: true
- [ ] Machine resource created
- [ ] Machine PHASE: Running
- [ ] KubeadmControlPlane INITIALIZED: true
- [ ] KubeadmControlPlane DESIRED = READY count
- [ ] Metal3Cluster READY: true
- [ ] Metal3Machine STATE: provisioned
- [ ] Kubeconfig accessible
- [ ] Workload cluster node accessible
- [ ] Workload cluster control plane pods running
- [ ] CNI installed (if node should be Ready)

---

## References

- [README.md](README.md) - Installation and usage guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Detailed troubleshooting procedures
- [Cluster API Documentation](../external/cluster-api/docs/)
- [CAPM3 Documentation](../external/cluster-api-provider-metal3/docs/)
- [Metal3 Documentation](../external/metal3-docs/)
