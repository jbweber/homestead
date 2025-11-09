# Metal3 Bare Metal Provisioning Setup

A comprehensive guide for deploying Metal3 (Bare Metal Operator + Ironic) on a single-node Kubernetes cluster for automated bare metal server provisioning.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Provisioning Workflow](#provisioning-workflow)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Overview

Metal3 provides Kubernetes-native declarative APIs for bare metal host provisioning. This setup uses:

- **Ironic** - OpenStack bare metal provisioning service (v32.0)
- **Bare Metal Operator (BMO)** - Kubernetes operator that manages BareMetalHost custom resources (v0.11.0)
- **Ironic Standalone Operator (IrSO)** - Operator for deploying and managing Ironic (v0.6.0)
- **cert-manager** - Automated TLS certificate management (v1.19.1)

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│ Kubernetes Control Plane (Single-Node)                  │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐                     │
│  │ IrSO         │  │ BMO          │                     │
│  │ Operator     │  │ Operator     │                     │
│  └──────┬───────┘  └──────┬───────┘                     │
│         │                  │                            │
│         │                  │ Reconciles state           │
│  ┌──────▼──────────────────▼───────┐                    │
│  │ Ironic (v32.0)                  │                    │
│  │ - API (port 6385)               │                    │
│  │ - HTTP server (ports 6180/6183)│                     │
│  │ - SQLite database (ephemeral)   │                    │
│  │ - TLS enabled                   │                    │
│  └─────────────────────────────────┘                    │
│                                                         │
│  cert-manager (TLS certificate management)              │
│  Flannel CNI (pod networking)                           │
│                                                         │
│  Source of Truth: BareMetalHost CRDs                    │
└─────────────────────────────────────────────────────────┘

External Infrastructure:
- DHCP server for provisioning network
- HTTP server for hosting OS images
- (Optional) TFTP server for PXE boot
```

### Network Architecture

**Required Networks:**
- **Provisioning Network** - Where bare metal hosts boot and get provisioned (e.g., 192.168.1.0/24)
- **Target Network** - Where deployed hosts run their production workloads (configured via cloud-init)

**Port Requirements:**

Accessible by bare metal hosts:
- TCP 6385 - Ironic API
- TCP 6180 - Ironic HTTP server (OS images, boot files)
- TCP 6183 - Ironic HTTPS server (TLS version)

Ironic must access:
- BMC ports: IPMI (623), Redfish (443), vendor-specific
- Port 9999 on hosts (IPA ramdisk callback during provisioning)

For network boot:
- UDP 67/68 - DHCP (external server)
- UDP 69 - TFTP (if using PXE; external server)

### Database and State Management

**Ephemeral SQLite Database:**
- Ironic uses in-container SQLite (no persistence)
- Database cleared on pod restart
- **Source of Truth: BareMetalHost CRDs in Kubernetes**

**Why This Works:**
- BMO automatically reconciles Ironic state from CRDs
- Provisioned hosts are re-adopted without reprovisioning
- Same approach used by OpenShift in production
- Lower resource footprint than persistent MariaDB
- No database backup/maintenance required

**BMO Reconciliation Process:**
1. Ironic pod restarts, database is empty
2. BMO detects discrepancy between CRDs and Ironic
3. BMO recreates all nodes in Ironic via API
4. Provisioned hosts: adopted without disruption
5. In-progress operations: restarted from scratch

## Prerequisites

### Hardware Requirements

**Control Plane Node:**
- 2-4 CPU cores
- 4-8 GB RAM
- 20 GB storage
- Network interface on provisioning network

**Bare Metal Hosts:**
- BMC with remote power management (IPMI, Redfish, iLO, iDRAC)
- Network boot capability (for PXE) OR virtual media support
- At least one network interface on provisioning network

### Software Requirements

- **Kubernetes cluster** (1.25+) with:
  - CNI plugin installed (Flannel, Calico, etc.)
  - Control plane node untainted (for single-node clusters)
- **kubectl** configured for cluster access
- **External DHCP server** configured for provisioning network
- **External HTTP server** for hosting OS images

### Network Configuration

1. **DHCP Server** - Provides IP addresses to bare metal hosts during provisioning
2. **Image Server** - Hosts OS images accessible via HTTP (e.g., `http://imageserver/images/fedora-43.raw`)
3. **DNS Resolution** - BMC hostnames resolvable from Kubernetes cluster (or use IP addresses)

## Installation

### Step 1: Install Kubernetes Cluster

Initialize a single-node Kubernetes cluster with a CNI plugin:

```bash
# Example: kubeadm init with Flannel
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel CNI
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Untaint control plane for single-node setup
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

**Verification:**
```bash
kubectl get nodes
# Should show: STATUS = Ready

kubectl get pods -A
# All pods should be Running
```

### Step 2: Install cert-manager

cert-manager automates TLS certificate creation and renewal:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml
```

**Wait for cert-manager to be ready:**
```bash
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager-cainjector -n cert-manager
```

**Verification:**
```bash
kubectl get pods -n cert-manager
# All pods should be Running
```

### Step 3: Install Ironic Standalone Operator (IrSO)

IrSO manages the Ironic deployment lifecycle:

```bash
kubectl apply -f https://github.com/metal3-io/ironic-standalone-operator/releases/download/v0.6.0/ironic-standalone-operator.yaml
```

**Wait for IrSO to be ready:**
```bash
kubectl wait --for=condition=Available --timeout=300s \
  deployment/ironic-standalone-operator-controller-manager \
  -n ironic-standalone-operator-system
```

**Verification:**
```bash
kubectl get pods -n ironic-standalone-operator-system
# Pod should be Running
```

### Step 4: Create TLS Certificate for Ironic

Create a self-signed certificate for Ironic's API and HTTP servers:

```yaml
# Save as ironic-tls-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ironic-selfsigned-issuer
  namespace: baremetal-operator-system
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ironic-cert
  namespace: baremetal-operator-system
spec:
  secretName: ironic-tls
  commonName: ironic.baremetal-operator-system.svc
  dnsNames:
    - ironic.baremetal-operator-system.svc
    - ironic.baremetal-operator-system.svc.cluster.local
  ipAddresses:
    - "192.168.1.10"  # Replace with your Kubernetes node IP
  issuerRef:
    name: ironic-selfsigned-issuer
    kind: Issuer
```

Apply the certificate:
```bash
kubectl create namespace baremetal-operator-system
kubectl apply -f ironic-tls-certificate.yaml
```

**Wait for certificate to be ready:**
```bash
kubectl wait --for=condition=Ready --timeout=300s \
  certificate/ironic-cert -n baremetal-operator-system
```

**Verification:**
```bash
kubectl get certificate -n baremetal-operator-system
# Should show: READY = True

kubectl get secret ironic-tls -n baremetal-operator-system
# Secret should exist
```

**Important:** IrSO does NOT automatically create Certificate resources. You must create the Certificate resource yourself, and cert-manager will generate the TLS secret that IrSO expects.

### Step 5: Deploy Ironic

Create the Ironic custom resource:

```yaml
# Save as ironic.yaml
apiVersion: ironic.metal3.io/v1alpha1
kind: Ironic
metadata:
  name: ironic
  namespace: baremetal-operator-system
spec:
  version: "32.0"

  # Network configuration
  networking:
    interface: "eth0"  # Replace with your network interface name
    ipAddress: "192.168.1.10"  # Replace with your node's IP address
    # For single-node: use host IP directly (no VIP/keepalived needed)
    # For multi-node HA: specify separate VIP and add ipAddressManager: keepalived

  # TLS configuration
  tls:
    certificateName: ironic-tls

  # (Optional) DHCP configuration - only needed if Ironic manages DHCP
  # If using external DHCP, omit this section
  # dhcp:
  #   rangeBegin: "192.168.1.100"
  #   rangeEnd: "192.168.1.199"
```

Apply the Ironic resource:
```bash
kubectl apply -f ironic.yaml
```

**Wait for Ironic to be ready:**
```bash
kubectl wait --for=condition=IronicReady --timeout=600s \
  ironic/ironic -n baremetal-operator-system
```

**Verification:**
```bash
kubectl get ironic -n baremetal-operator-system
# Should show: READY = true

kubectl get pods -n baremetal-operator-system | grep ironic
# Pod should be Running with 3/3 containers
```

**Get Ironic credentials:**
```bash
SECRET=$(kubectl get ironic/ironic -n baremetal-operator-system --template='{{.spec.apiCredentialsName}}')
echo "Username: $(kubectl get secret ${SECRET} -n baremetal-operator-system -o jsonpath='{.data.username}' | base64 -d)"
echo "Password: $(kubectl get secret ${SECRET} -n baremetal-operator-system -o jsonpath='{.data.password}' | base64 -d)"
```

### Step 6: Install Bare Metal Operator (BMO)

BMO manages BareMetalHost custom resources and communicates with Ironic:

```bash
# Create kustomization.yaml
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: baremetal-operator-system

resources:
  - https://github.com/metal3-io/baremetal-operator/config/namespace?ref=v0.11.0
  - https://github.com/metal3-io/baremetal-operator/config/crd?ref=v0.11.0
  - https://github.com/metal3-io/baremetal-operator/config/rbac?ref=v0.11.0
  - https://github.com/metal3-io/baremetal-operator/config/manager?ref=v0.11.0
  - https://github.com/metal3-io/baremetal-operator/config/certmanager?ref=v0.11.0
  - https://github.com/metal3-io/baremetal-operator/config/webhook?ref=v0.11.0

components:
  - https://github.com/metal3-io/baremetal-operator/config/components/basic-auth?ref=v0.11.0
  - https://github.com/metal3-io/baremetal-operator/config/components/tls?ref=v0.11.0

configMapGenerator:
  - name: ironic
    behavior: create
    literals:
      - DEPLOY_KERNEL_URL=http://192.168.1.10:6180/images/ironic-python-agent.kernel
      - DEPLOY_RAMDISK_URL=http://192.168.1.10:6180/images/ironic-python-agent.initramfs
      - IRONIC_ENDPOINT=https://ironic.baremetal-operator-system.svc:6385/v1/
      - IRONIC_INSPECTOR_ENDPOINT=https://ironic.baremetal-operator-system.svc:5050/v1/
      - IRONIC_CACERT_FILE=/opt/metal3/certs/ca/tls.crt

secretGenerator:
  - name: ironic-credentials
    behavior: create
    literals:
      - username=REPLACE_WITH_IRONIC_USERNAME
      - password=REPLACE_WITH_IRONIC_PASSWORD
EOF

# Get Ironic credentials
SECRET=$(kubectl get ironic/ironic -n baremetal-operator-system --template='{{.spec.apiCredentialsName}}')
IRONIC_USERNAME=$(kubectl get secret ${SECRET} -n baremetal-operator-system -o jsonpath='{.data.username}' | base64 -d)
IRONIC_PASSWORD=$(kubectl get secret ${SECRET} -n baremetal-operator-system -o jsonpath='{.data.password}' | base64 -d)

# Replace credentials in kustomization.yaml
sed -i "s/REPLACE_WITH_IRONIC_USERNAME/${IRONIC_USERNAME}/" kustomization.yaml
sed -i "s/REPLACE_WITH_IRONIC_PASSWORD/${IRONIC_PASSWORD}/" kustomization.yaml

# Replace IP address with your node IP
sed -i "s/192.168.1.10/YOUR_NODE_IP/g" kustomization.yaml

# Apply BMO
kubectl apply -k .
```

**Wait for BMO to be ready:**
```bash
kubectl wait --for=condition=Available --timeout=300s \
  deployment/baremetal-operator-controller-manager \
  -n baremetal-operator-system
```

**Verification:**
```bash
kubectl get pods -n baremetal-operator-system
# BMO pod should be Running

kubectl logs -n baremetal-operator-system deployment/baremetal-operator-controller-manager
# Should show successful connection to Ironic
```

**Critical Configuration Note:** The BMO ConfigMap must use the correct CA certificate path:
```yaml
IRONIC_CACERT_FILE: /opt/metal3/certs/ca/tls.crt  # Correct path matching volume mount
```

If BMO shows "microversions not supported by endpoint" errors, verify this path is correct.

## Configuration

### Virtual IP Address (VIP) Configuration

**Single-Node Cluster (Recommended for Lab/Testing):**
- Use the host's IP address directly
- No VIP or keepalived needed
- Pod can't move to another node

```yaml
networking:
  interface: "eth0"
  ipAddress: "192.168.1.10"  # Host IP directly
```

**Multi-Node Cluster with High Availability:**
- Use a separate VIP that floats between nodes
- Enable keepalived for VIP management
- VIP follows Ironic pod if it moves

```yaml
networking:
  interface: "eth0"
  ipAddress: "192.168.1.240"  # Separate VIP
  ipAddressManager:
    keepalived: {}
```

**VIP Requirements:**
- Only needed for multi-node clusters
- Only needed for network boot (PXE/iPXE)
- Not needed for virtual media provisioning (BMC makes outbound connections)

### Boot Method Configuration

Metal3 supports two boot methods:

**1. Virtual Media (Default, Recommended):**
- BMC mounts ISO image from Ironic's HTTP server
- Simpler setup, works with modern BMCs (Redfish, iLO, iDRAC)
- No PXE/TFTP configuration needed
- Uses external DHCP only for OS networking

**2. Network Boot (PXE/iPXE):**
- Requires DHCP server with TFTP/HTTP boot options
- Supports older hardware without virtual media
- More complex setup

**For PXE Boot, configure external DHCP server to:**
1. Serve initial iPXE bootloader via TFTP
2. Chain to Ironic's HTTP endpoint: `http://<ironic-ip>:6180/boot.ipxe`
3. iPXE downloads IPA kernel/ramdisk from Ironic

Example dnsmasq configuration:
```conf
# DHCP configuration
dhcp-range=192.168.1.100,192.168.1.199,24h

# Detect client architecture
dhcp-match=set:efi,option:client-arch,7
dhcp-match=set:efi,option:client-arch,9
dhcp-match=set:efi,option:client-arch,11

# Initial boot via TFTP
dhcp-boot=tag:efi,tag:!ipxe,snponly.efi,192.168.1.20
dhcp-boot=tag:!efi,tag:!ipxe,undionly.kpxe,192.168.1.20

# Chain to Ironic HTTP after iPXE loads
dhcp-boot=tag:ipxe,http://192.168.1.10:6180/boot.ipxe
```

### OS Image Hosting

OS images must be accessible via HTTP from the provisioning network:

1. **Supported Formats:**
   - Raw disk images (`.raw`, `.img`)
   - qcow2 images (`.qcow2`)
   - Compressed formats (`.gz`, `.xz`)

2. **Image Requirements:**
   - cloud-init installed and enabled
   - SSH server enabled
   - Root filesystem partition expandable

3. **Checksum Files:**
   - Provide SHA256 checksum for image verification
   - Format: `<sha256sum>  <filename>`
   - Example: `fedora-43.raw.sha256sum`

4. **Hosting Setup:**
   ```bash
   # Example: nginx serving images
   sudo mkdir -p /var/www/images
   sudo cp fedora-43.raw /var/www/images/
   sha256sum /var/www/images/fedora-43.raw > /var/www/images/fedora-43.raw.sha256sum
   ```

## Provisioning Workflow

### Overview

The complete provisioning lifecycle:

```
1. Registration → 2. Inspection → 3. Available → 4. Provisioning → 5. Provisioned
      ↓                  ↓               ↓              ↓                ↓
  BMC access       Hardware scan    Ready to use    OS install      Running OS
   verified         (IPA boot)                      (IPA boot)
```

### 1. Create BMC Credentials Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: server01-bmc-secret
  namespace: baremetal-operator-system
type: Opaque
stringData:
  username: "admin"
  password: "changeme"
```

### 2. Create BareMetalHost Resource

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: server01
  namespace: baremetal-operator-system
spec:
  online: true
  bootMACAddress: "52:54:00:12:34:56"
  bootMode: UEFI

  bmc:
    address: redfish-virtualmedia://server01-bmc.example.com
    credentialsName: server01-bmc-secret
    disableCertificateVerification: true

  automatedCleaningMode: metadata

  # Optional: specify target disk for multi-disk systems
  rootDeviceHints:
    minSizeGigabytes: 100
    # OR: deviceName: /dev/nvme0n1
    # OR: rotational: false  # For SSD/NVMe only
```

**Determining BMC Protocol:**

| Hardware Vendor | BMC Type | Protocol |
|-----------------|----------|----------|
| Dell | iDRAC 9+ | `redfish-virtualmedia://` or `idrac-virtualmedia://` |
| HPE | iLO 5+ | `ilo5-virtualmedia://` |
| HPE | iLO 4 | `ilo4-virtualmedia://` |
| Supermicro | Redfish | `redfish-virtualmedia://` or `redfish://` |
| Generic/Unknown | IPMI | `ipmi://` |

**Testing BMC Connectivity:**
```bash
# Test Redfish
curl -k -u admin:password https://server01-bmc.example.com/redfish/v1/

# Test IPMI
ipmitool -I lanplus -H server01-bmc.example.com -U admin -P password power status
```

### 3. Monitor Registration and Inspection

```bash
# Watch host state changes
kubectl get baremetalhost server01 -n baremetal-operator-system -w

# Check detailed status
kubectl describe baremetalhost server01 -n baremetal-operator-system

# View hardware inventory after inspection
kubectl get hardwaredata server01 -n baremetal-operator-system -o yaml
```

**Expected States:**
- `registering` - BMO verifying BMC access (1-2 minutes)
- `inspecting` - IPA collecting hardware inventory (5-10 minutes)
- `available` - Ready for provisioning

### 4. Provision with OS Image

Create cloud-init configuration:

```yaml
# user-data-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: server01-user-data
  namespace: baremetal-operator-system
type: Opaque
stringData:
  value: |
    #cloud-config
    users:
      - name: admin
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2E... user@example.com

    hostname: server01.example.com

    # Disable cloud-init after first boot
    bootcmd:
      - cloud-init-per once disable-cloud-init touch /etc/cloud/cloud-init.disabled
```

Optional: Create network configuration (OpenStack network_data.json format):

```yaml
# network-data-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: server01-network-data
  namespace: baremetal-operator-system
type: Opaque
stringData:
  value: |
    {
      "links": [
        {
          "id": "nic1",
          "type": "phy",
          "ethernet_mac_address": "52:54:00:12:34:56"
        }
      ],
      "networks": [
        {
          "id": "network1",
          "type": "ipv4",
          "link": "nic1",
          "ip_address": "192.168.1.100",
          "netmask": "255.255.255.0",
          "gateway": "192.168.1.1",
          "dns_nameservers": ["192.168.1.1"]
        }
      ]
    }
```

Update BareMetalHost with image spec:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: server01
  namespace: baremetal-operator-system
spec:
  online: true
  bootMACAddress: "52:54:00:12:34:56"
  bootMode: UEFI

  bmc:
    address: redfish-virtualmedia://server01-bmc.example.com
    credentialsName: server01-bmc-secret
    disableCertificateVerification: true

  automatedCleaningMode: metadata

  # Image specification
  image:
    url: http://imageserver.example.com/images/fedora-43.raw
    checksum: http://imageserver.example.com/images/fedora-43.raw.sha256sum
    checksumType: sha256
    format: raw

  # Cloud-init configuration
  userData:
    name: server01-user-data
    namespace: baremetal-operator-system

  # Optional: network configuration
  networkData:
    name: server01-network-data
    namespace: baremetal-operator-system
```

### 5. Monitor Provisioning

```bash
# Watch provisioning progress
kubectl get baremetalhost server01 -n baremetal-operator-system -w

# Check detailed status
kubectl get baremetalhost server01 -n baremetal-operator-system -o yaml

# Monitor Ironic logs
kubectl logs -n baremetal-operator-system <ironic-pod-name> -c ironic -f
```

**Provisioning stages:**
- `provisioning` - IPA booting and writing image to disk (10-30 minutes depending on image size)
- `provisioned` - OS deployed, host rebooted into production OS

### Understanding IPA (Ironic Python Agent)

**Key Points:**
- IPA is a ramdisk-based agent, NOT a persistent service
- Runs only during provisioning phases (inspection, deployment, cleaning)
- Exits after provisioning completes
- No ongoing agent or heartbeat on deployed hosts
- Completely different from configuration management agents (Puppet, Chef, Ansible)

**IPA Lifecycle:**
1. BMC boots host to IPA ramdisk (via virtual media or PXE)
2. IPA runs in memory, performs task (inspect hardware, write image, clean disk)
3. IPA reports completion to Ironic
4. Host reboots into deployed OS (or powers off)
5. IPA is gone, no agent remains on host

## Troubleshooting

### Host Stuck in "registering"

**Symptoms:**
- BareMetalHost remains in `registering` state for >5 minutes
- Status message: "registering"

**Possible Causes:**
1. BMC not reachable from Kubernetes cluster
2. Invalid BMC credentials
3. Wrong BMC protocol specified

**Debugging:**
```bash
# Check BMO logs
kubectl logs -n baremetal-operator-system deployment/baremetal-operator-controller-manager -f

# Test BMC connectivity from Kubernetes node
ping server01-bmc.example.com
curl -k https://server01-bmc.example.com

# Test BMC credentials manually
# Redfish:
curl -k -u admin:password https://server01-bmc.example.com/redfish/v1/Systems

# IPMI:
ipmitool -I lanplus -H server01-bmc.example.com -U admin -P password power status

# Check BareMetalHost status
kubectl describe baremetalhost server01 -n baremetal-operator-system
```

**Solutions:**
- Verify BMC hostname/IP is resolvable and reachable
- Verify credentials in secret
- Try alternative BMC protocols (e.g., `redfish://` instead of `redfish-virtualmedia://`)

### Host Stuck in "inspecting"

**Symptoms:**
- BareMetalHost stuck in `inspecting` state for >30 minutes
- No hardware inventory populated

**Possible Causes:**
1. IPA ramdisk failed to boot
2. IPA can't reach Ironic API
3. Network connectivity issues
4. BMC virtual media not working

**Debugging:**
```bash
# Check Ironic logs
kubectl logs -n baremetal-operator-system <ironic-pod-name> -c ironic -f

# For virtual media boot:
# - Access BMC web interface
# - Check virtual media status (should show ISO mounted)

# For network boot:
# - Check DHCP logs on external DHCP server
# - Verify PXE boot files are accessible

# Verify Ironic HTTP endpoints are accessible
curl http://192.168.1.10:6180/images/ironic-python-agent.kernel
curl http://192.168.1.10:6180/images/ironic-python-agent.initramfs
curl http://192.168.1.10:6180/boot.ipxe
```

**Solutions:**
- Ensure IPA ramdisk images are present in Ironic pod
- Verify network connectivity between bare metal host and Ironic
- Check BMC supports virtual media (try PXE boot instead)
- Verify Ironic API is accessible from provisioning network

### Provisioning Fails with Disk Errors

**Symptoms:**
- Error: "lsblk: /dev/sda: not a block device"
- Error: "No valid root device found"

**Cause:**
- System has multiple disks
- Ironic defaulted to wrong disk (e.g., USB drive instead of NVMe)

**Solution:**
Add `rootDeviceHints` to BareMetalHost spec:

```yaml
spec:
  # Check hardware inventory first
  rootDeviceHints:
    deviceName: /dev/nvme0n1
    # OR use size/type hints:
    # minSizeGigabytes: 100
    # rotational: false  # SSD/NVMe only
```

**Find available disks:**
```bash
kubectl get hardwaredata server01 -n baremetal-operator-system -o jsonpath='{.spec.hardware.storage}' | jq .
```

### Error: "microversions not supported by endpoint"

**Symptoms:**
- BareMetalHost stuck in `registering`
- BMO logs show: "error caught while checking endpoint, will retry: microversions not supported by endpoint"

**Cause:**
- Incorrect CA certificate path in BMO ConfigMap

**Solution:**
```bash
# Check current path
kubectl get configmap ironic -n baremetal-operator-system -o yaml | grep CACERT

# Should show: /opt/metal3/certs/ca/tls.crt
# If it shows: /certs/ca/tls.crt (wrong!)

# Fix with patch:
kubectl patch configmap ironic -n baremetal-operator-system \
  --type merge -p '{"data":{"IRONIC_CACERT_FILE":"/opt/metal3/certs/ca/tls.crt"}}'

# Restart BMO
kubectl rollout restart deployment/baremetal-operator-controller-manager \
  -n baremetal-operator-system
```

### TLS Certificate Issues

**Symptoms:**
- Ironic deployment stuck with "secret not found" error
- cert-manager Certificate shows "Ready = False"

**Cause:**
- Certificate not created before deploying Ironic
- cert-manager not functioning properly

**Solution:**
```bash
# Check cert-manager pods
kubectl get pods -n cert-manager
# All should be Running

# Check Certificate status
kubectl get certificate -n baremetal-operator-system
kubectl describe certificate ironic-cert -n baremetal-operator-system

# Check if secret was created
kubectl get secret ironic-tls -n baremetal-operator-system

# Recreate certificate if needed
kubectl delete certificate ironic-cert -n baremetal-operator-system
kubectl apply -f ironic-tls-certificate.yaml
```

**Important:** IrSO does NOT auto-create Certificate resources. The `tls.certificateName` field only tells IrSO which secret to use. You must create the Certificate resource yourself.

### Checking Overall System Health

```bash
# Check all pods
kubectl get pods -A

# Check Metal3 components
kubectl get pods -n baremetal-operator-system
kubectl get pods -n ironic-standalone-operator-system
kubectl get pods -n cert-manager

# Check Ironic status
kubectl get ironic -n baremetal-operator-system

# Check BareMetalHost resources
kubectl get baremetalhost -A

# Check recent events
kubectl get events -n baremetal-operator-system --sort-by='.lastTimestamp'
```

## Key Concepts and Design Decisions

### Why Ephemeral Database?

**Decision:** Use SQLite in container (ephemeral) instead of persistent MariaDB

**Rationale:**
- BareMetalHost CRDs in Kubernetes are the source of truth
- BMO automatically reconciles Ironic state from CRDs
- Provisioned hosts are re-adopted without reprovisioning
- Same approach used by OpenShift in production
- Lower resource footprint
- No database backup/maintenance overhead

**When to use MariaDB instead:**
- NOT using BMO (direct Ironic API usage)
- Need audit trails in Ironic database
- Specific compliance requirements

### Single-Node vs Multi-Node

**Single-Node Setup:**
- Use host IP directly (no VIP)
- Simpler configuration
- Suitable for lab/testing environments
- Still fully functional for production with appropriate hardware

**Multi-Node HA Setup:**
- Use separate VIP with keepalived
- Required only if Ironic pod needs to move between nodes
- Required only for network boot scenarios
- Not required for virtual media (BMC makes outbound connections)

### Virtual Media vs Network Boot

**Virtual Media (Recommended):**
- BMC mounts ISO from Ironic HTTP server
- Simpler setup
- Works with modern BMCs (Redfish, iLO 5+, iDRAC 9+)
- No PXE/TFTP configuration needed
- Lower network traffic

**Network Boot (PXE/iPXE):**
- Requires DHCP + TFTP/HTTP configuration
- Supports older hardware without virtual media
- More flexible for environments with existing PXE infrastructure
- Higher network traffic during boot

## References

### Official Documentation

- [Metal3 Project](https://metal3.io/) - Official project website
- [Bare Metal Operator](https://github.com/metal3-io/baremetal-operator) - BMO repository and documentation
- [Ironic Standalone Operator](https://github.com/metal3-io/ironic-standalone-operator) - IrSO repository
- [OpenStack Ironic](https://docs.openstack.org/ironic/latest/) - Ironic project documentation

### API References

- [BareMetalHost API](https://github.com/metal3-io/baremetal-operator/blob/main/docs/api.md) - Complete BMH spec documentation
- [Ironic CR API](https://github.com/metal3-io/ironic-standalone-operator/blob/main/docs/api.md) - Ironic custom resource spec
- [Root Device Hints](https://github.com/metal3-io/baremetal-operator/blob/main/docs/root_device_hints.md) - Disk selection options

### Component Documentation

- [cert-manager](https://cert-manager.io/docs/) - TLS certificate management
- [cloud-init](https://cloudinit.readthedocs.io/) - OS initialization and configuration
- [Ironic Python Agent (IPA)](https://docs.openstack.org/ironic-python-agent/latest/) - Provisioning agent

### Related Projects

- [Cluster API Provider Metal3](https://github.com/metal3-io/cluster-api-provider-metal3) - Kubernetes cluster provisioning with Metal3
- [kube-vip](https://kube-vip.io/) - Alternative VIP solution for Kubernetes
- [MetalLB](https://metallb.universe.tf/) - Load balancer for bare metal Kubernetes

### Community

- [Metal3 Slack](https://kubernetes.slack.com/messages/CHD49TLE7) - #cluster-api-baremetal channel
- [Metal3 Mailing List](https://groups.google.com/g/metal3-dev) - Development discussions
- [Metal3 Community Meetings](https://github.com/metal3-io/community) - Weekly community calls

---

**Document Version:** 2.0
**Last Updated:** 2025-01-09
**Based on:** Metal3 BMO v0.11.0, IrSO v0.6.0, Ironic v32.0
