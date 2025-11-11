# Cluster API Troubleshooting Guide

This document provides detailed troubleshooting solutions for common issues encountered when working with Cluster API and Metal3.

For basic validation procedures, see [VALIDATION.md](VALIDATION.md).

---

## Provider Installation Issues

### Provider installation fails

**Symptoms**: Provider deployments fail to start or remain in CrashLoopBackOff

**Check cert-manager is running**:
```bash
kubectl get pods -n cert-manager
```

All cert-manager pods must be Running before installing CAPI providers.

**Check provider logs**:
```bash
# CAPI core logs
kubectl logs -n capi-system deployment/capi-controller-manager

# Metal3 provider logs
kubectl logs -n capm3-system deployment/capm3-controller-manager

# Bootstrap provider logs
kubectl logs -n capi-kubeadm-bootstrap-system deployment/capi-kubeadm-bootstrap-controller-manager
```

Look for webhook certificate errors or API connectivity issues.

---

## Cluster Deployment Issues

### Cluster creation stalled

**Symptoms**: Cluster resource created but no progress visible

**Check BareMetalHost status**:
```bash
kubectl get baremetalhosts -A -o wide
```

Ensure at least one host is in "available" state.

**Check Machine status**:
```bash
kubectl get machines -n default -o wide
```

Look for error messages in the Machine status.

**Check CAPM3 controller logs**:
```bash
kubectl logs -n capm3-system deployment/capm3-controller-manager -f
```

Watch for errors related to host selection or provisioning.

---

### No BareMetalHosts available

**Symptoms**: `kubectl get baremetalhosts -A` shows no hosts in "available" state

**Possible states**:
- **ready**: Host is registered but never provisioned (deprovision to make available)
- **provisioned**: Host is in use by another cluster
- **provisioning**: Host is currently being provisioned
- **deprovisioning**: Host is being cleaned and will become available
- **inspecting**: Host is being inspected (hardware discovery)

**Solution**: If hosts are in "ready" state and not in use, they need to be deprovisioned first:

```bash
# Check current state
kubectl get baremetalhost <host-name> -n default -o jsonpath='{.status.provisioning.state}'

# If in "ready", deprovision to make available
kubectl annotate baremetalhost <host-name> -n default \
  reboot.metal3.io/capbm=''
```

Wait for host to transition through "deprovisioning" → "available".

---

### Metal3Machine fails with "No available host found"

**Symptoms**: Metal3Machine shows error message:
```
No available host found. Requeuing..
```

**Root Cause**: The `hostSelector` in Metal3MachineTemplate doesn't match any BareMetalHost labels.

**Diagnosis**:

1. **Check Metal3Machine hostSelector**:
```bash
kubectl get metal3machine <machine-name> -n default -o yaml | grep -A5 hostSelector
```

Example output:
```yaml
hostSelector:
  matchLabels:
    name: super
```

2. **Check BareMetalHost labels**:
```bash
kubectl get baremetalhost <host-name> -n default --show-labels
```

If the BareMetalHost doesn't have a `name=super` label, it won't match.

**Solution**: Add matching label to BareMetalHost:

```bash
kubectl label baremetalhost <host-name> -n default name=<value>
```

Example:
```bash
kubectl label baremetalhost super -n default name=super
```

**Verification**:
```bash
# Verify label was added
kubectl get baremetalhost super -n default --show-labels

# Watch Metal3Machine pick up the host
kubectl get metal3machine -n default -w
```

---

### BareMetalHost stuck in "provisioning" but not powered on

**Symptoms**:
- BareMetalHost shows `state: provisioning`
- But `poweredOn: false` and no progress
- Bare Metal Operator logs show:
  ```
  could not update node settings in ironic, busy or update cannot be applied in the current state
  ```
- Ironic logs show:
  ```
  Node <uuid> is associated with instance <old-instance-uuid>
  ```

**Root Cause**: After deleting a cluster, the Ironic node retains a stale instance UUID in its in-memory database. The BMO cannot update the node with the new instance UUID because Ironic thinks the node is still in use.

Ironic uses an in-memory SQLite database that persists node instance associations across cluster deletions. When a cluster is deleted, the BareMetalHost returns to "available" state, but the Ironic node record still has the old `instance_uuid` set.

**Solution**: Restart the Ironic deployment to clear the in-memory database:

```bash
# Rolling restart of Ironic
kubectl rollout restart deployment/ironic-service -n baremetal-operator-system

# Wait for rollout to complete (new pod running)
kubectl rollout status deployment/ironic-service -n baremetal-operator-system

# Check new pod is running
kubectl get pods -n baremetal-operator-system -l ironic.metal3.io/app=ironic-service

# Watch BareMetalHost state transition
watch kubectl get baremetalhost <host-name> -n default -o jsonpath='{.status.provisioning.state}'
```

**Expected behavior after restart**:
1. Ironic restarts with a clean in-memory database
2. BareMetalHost transitions to "clean wait" state (automated cleaning)
3. After cleaning completes (5-10 minutes), host becomes "available"
4. BMO can now provision the host with the new instance UUID
5. Host powers on and begins provisioning

**Prevention**: This issue occurs when quickly redeploying clusters. To avoid it in production:
- Allow sufficient time between cluster deletion and recreation (wait for "available")
- Monitor BareMetalHost state before redeploying
- Consider using a persistent Ironic database (not in-memory SQLite) for production environments

**Verification**:

Check Bare Metal Operator logs for successful provisioning:
```bash
kubectl logs -n baremetal-operator-system deployment/baremetal-operator-controller-manager --tail=100 | grep <host-name>
```

Look for these progression indicators:
- `"provisioning image to host"` - BMO starting provisioning
- `"state":"clean wait"` - Host in cleaning phase
- `"current":"available"` - Host ready for provisioning
- `"current":"deploying"` - Host actively deploying

---

## Kubernetes Initialization Issues

### kubeadm init fails with DNS resolution errors

**Symptoms**: During provisioning, kubeadm init fails with DNS errors like:
```
failed to pull image registry.k8s.io/kube-apiserver:v1.34.1:
dial tcp: lookup registry.k8s.io: Temporary failure in name resolution
```

**Root Cause**: Race condition between NetworkManager bringing up the network interface and systemd-resolved becoming ready to serve DNS queries. This typically occurs when using nmcli to configure networking in `preKubeadmCommands`.

The network is configured correctly, but systemd-resolved needs a few seconds to pick up the DNS configuration from NetworkManager.

**Solution**: Add a DNS readiness wait in `preKubeadmCommands` before kubeadm init runs:

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
spec:
  kubeadmConfigSpec:
    preKubeadmCommands:
      # ... network configuration with nmcli ...

      # Wait for DNS to be ready (systemd-resolved needs time to sync)
      - for i in {1..30}; do if getent hosts registry.k8s.io > /dev/null 2>&1; then echo "DNS ready"; break; fi; echo "Waiting for DNS ($i/30)..."; sleep 2; done
      - if ! getent hosts registry.k8s.io > /dev/null 2>&1; then echo "ERROR DNS not ready after 60 seconds"; exit 1; fi
```

This waits up to 60 seconds (30 iterations × 2 seconds) for DNS to become functional before proceeding with kubeadm init.

**How it works**:
1. Loop checks if `registry.k8s.io` (or any common hostname) resolves
2. Retries every 2 seconds for up to 60 seconds
3. Fails fast if DNS doesn't work after timeout
4. Provides clear error message for debugging

**Prevention**: This issue occurs when manually configuring networking with nmcli instead of using DHCP or Metal3DataTemplate networkData. Always add DNS readiness checks when using custom network configuration in preKubeadmCommands.

**Alternative DNS checks**:
```bash
# Check specific domain
getent hosts registry.k8s.io

# Check DNS server directly
dig @192.168.1.1 registry.k8s.io

# Check systemd-resolved status
resolvectl status
```

---

### Kubeconfig not generated

**Symptoms**: Cluster appears to be provisioning but kubeconfig is not available

**Root Cause**: The kubeconfig is created once the control plane is fully initialized. This can take 15-30 minutes for bare metal provisioning (PXE boot, OS installation, kubeadm init).

**Check control plane status**:
```bash
kubectl get kubeadmcontrolplane -n default
```

Look for `Ready: true` and `Replicas: 1/1` (or your desired replica count).

**Check Machine status**:
```bash
kubectl get machines -n default -o wide
```

Look for Phase: "Running" and node reference populated.

**Manually retrieve kubeconfig**:
```bash
clusterctl get kubeconfig <cluster-name> -n default > kubeconfig.yaml

# Test access
KUBECONFIG=kubeconfig.yaml kubectl get nodes
```

**Timeline expectations**:
- **0-5 min**: BareMetalHost provisioning (PXE boot, image download)
- **5-15 min**: OS installation and first boot
- **15-25 min**: cloud-init runs preKubeadmCommands, kubeadm init
- **25-30 min**: Control plane ready, kubeconfig available

---

## Network Configuration Issues

### RECOMMENDED: Use BMH networkData Approach

For all new deployments, use the **BMH networkData approach** (pre-configure network on BareMetalHost before CAPI claims it). This works for both simple and complex configurations and avoids Metal3DataTemplate bugs.

See [README.md - Network Configuration](README.md#network-configuration) for the recommended approach with examples.

### LEGACY: Metal3DataTemplate networkData not working for bonds/VLANs

**Note**: This section is kept for reference for existing deployments. New deployments should use the BMH networkData approach instead.

**Symptoms**: Network configuration using Metal3DataTemplate's `networkData` field fails with bonds or VLANs. Cloud-init generates broken network configuration with literal "None" interfaces.

**Root Cause**: Metal3 renders networkData in the wrong order (bonds before physical interfaces), causing cloud-init to fail when processing forward references. This is a known issue with the Metal3DataTemplate networkData rendering for complex network configurations.

**Legacy Solution**: Use nmcli commands in `preKubeadmCommands` (DEPRECATED - use BMH networkData instead).

**Recommended approach for bond + VLAN configuration**:

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
spec:
  kubeadmConfigSpec:
    preKubeadmCommands:
      # Configure bond
      - nmcli con add type bond ifname bond0 con-name bond0 mode active-backup miimon 100
      - nmcli con add type ethernet ifname eno1 con-name bond0-slave1 master bond0
      - nmcli con add type ethernet ifname eno3 con-name bond0-slave2 master bond0
      - nmcli con modify bond0 ipv4.method disabled ipv6.method ignore

      # Configure VLAN
      - nmcli con add type vlan ifname bond0.2000 con-name bond0.2000 id 2000 dev bond0
      - nmcli con modify bond0.2000 ipv4.addresses 192.168.1.100/24 ipv4.gateway 192.168.1.1 ipv4.dns "192.168.1.1" ipv4.method manual

      # Bring up interfaces
      - nmcli con up bond0-slave1
      - nmcli con up bond0-slave2
      - nmcli con up bond0
      - nmcli con up bond0.2000

      # Wait for DNS readiness (important!)
      - for i in {1..30}; do if getent hosts registry.k8s.io > /dev/null 2>&1; then echo "DNS ready"; break; fi; echo "Waiting for DNS ($i/30)..."; sleep 2; done
```

**Why nmcli approach worked** (legacy):
- Bypassed Metal3's buggy network rendering
- Used native NetworkManager (standard on Fedora/RHEL)
- Commands execute in order (imperative, not declarative)
- Easy to debug with `nmcli con show`

**Current recommendation**: Use BMH networkData for all configurations (simple and complex). It's cleaner, easier to maintain, and works reliably for bonds, VLANs, and all network types.

---

## Validation and Monitoring

### Check overall cluster health

Use the provided health check script:
```bash
./validate-health.sh
```

### Monitor provisioning progress

Watch all key resources:
```bash
# Watch cluster
watch kubectl get cluster -n default

# Watch machines
watch kubectl get machines -n default

# Watch BareMetalHost
watch kubectl get baremetalhosts -A

# Watch control plane
watch kubectl get kubeadmcontrolplane -n default
```

### Access component logs

```bash
# CAPI core controller
kubectl logs -n capi-system deployment/capi-controller-manager -f

# Metal3 infrastructure provider
kubectl logs -n capm3-system deployment/capm3-controller-manager -f

# Bootstrap provider
kubectl logs -n capi-kubeadm-bootstrap-system deployment/capi-kubeadm-bootstrap-controller-manager -f

# Control plane provider
kubectl logs -n capi-kubeadm-control-plane-system deployment/capi-kubeadm-control-plane-controller-manager -f

# Bare Metal Operator
kubectl logs -n baremetal-operator-system deployment/baremetal-operator-controller-manager -f

# Ironic
kubectl logs -n baremetal-operator-system deployment/ironic-service -f
```

---

## Additional Resources

- [README.md](README.md) - Installation and usage guide
- [VALIDATION.md](VALIDATION.md) - Comprehensive validation procedures
- [Cluster API Troubleshooting](https://cluster-api.sigs.k8s.io/user/troubleshooting.html)
- [Metal3 Troubleshooting](https://book.metal3.io/troubleshooting.html)
