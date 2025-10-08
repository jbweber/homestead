# KubeVirt Architecture Deep Dive

A hands-on guide to understanding how KubeVirt runs virtual machines in Kubernetes.

## Overview

KubeVirt allows you to run traditional virtual machines alongside containers in Kubernetes. It does this by:
1. Creating a standard Kubernetes pod for each VM
2. Running libvirt inside that pod
3. Using QEMU/KVM to run the actual virtual machine

## The Component Stack

### Communication Between virt-handler and virt-launcher

**Yes, they communicate directly via Unix domain sockets!**

virt-handler does NOT just create the pod and walk away. It actively monitors and manages the VM through direct socket communication:

- **virt-launcher** creates a socket at `/var/run/kubevirt/domain-notify-pipe.sock` inside the pod
- **virt-handler** accesses this socket through a **hostPath mount** of `/var/run/kubevirt` on the node
- virt-handler uses this socket to receive notifications about domain state changes
- virt-handler also queries libvirt directly through the pod's filesystem to sync VM state

**How to verify this:**

```bash
# Inside virt-launcher pod - see the notify socket
POD=$(kubectl get pod -l kubevirt.io/vm=vm-01 -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- ls -la /var/run/kubevirt/
# Shows: domain-notify-pipe.sock

# Check virt-handler hostPath mounts
kubectl get pod -n kubevirt -l kubevirt.io=virt-handler -o yaml | grep -A 5 "hostPath:"
# Shows: /var/run/kubevirt mounted from host

# Inside virt-handler pod - same socket accessible
HANDLER_POD=$(kubectl get pod -n kubevirt -l kubevirt.io=virt-handler -o jsonpath='{.items[0].metadata.name}' --field-selector spec.nodeName=super.fe.cofront.xyz)
kubectl exec -n kubevirt $HANDLER_POD -- ls -la /var/run/kubevirt/
# Shows: domain-notify.sock (same socket, different view)

# Watch virt-handler sync with domains
kubectl logs -n kubevirt -l kubevirt.io=virt-handler --tail=20 | grep "resyncing"
# Shows: "resyncing virt-launcher domains" every 5 minutes
```

The architecture is:
1. virt-launcher runs in the pod with `/var/run/kubevirt` as an emptyDir volume
2. The kubelet bind-mounts this into the host at `/var/run/kubevirt/<pod-uid>/`
3. virt-handler mounts the host's `/var/run/kubevirt` via hostPath and can access all VM sockets
4. This allows virt-handler to monitor/control VMs while maintaining pod isolation

**Reference:** The communication model is mentioned in [KubeVirt GitHub Issue #937](https://github.com/kubevirt/kubevirt/issues/937) discussing virt-launcher/virt-handler communication.

### Cluster-Wide Components

**virt-controller**
- Watches for VirtualMachine (VM) resources
- Creates virt-launcher pods when VMs are requested
- Manages VM lifecycle at the cluster level

```bash
# View virt-controller pods
kubectl get pods -n kubevirt -l kubevirt.io=virt-controller

# Check virt-controller logs
kubectl logs -n kubevirt -l kubevirt.io=virt-controller
```

**virt-handler** (DaemonSet)
- Runs on every node
- Manages VMs running on that specific node
- Communicates with virt-launcher pods
- Reports node capabilities

```bash
# View virt-handler pods (one per node)
kubectl get pods -n kubevirt -l kubevirt.io=virt-handler -o wide

# Check virt-handler logs on a specific node
kubectl logs -n kubevirt -l kubevirt.io=virt-handler --tail=50
```

**virt-api**
- REST API for VM operations
- Webhook validations
- Subresource endpoints (VNC, console, etc.)

```bash
# View virt-api pods
kubectl get pods -n kubevirt -l kubevirt.io=virt-api

# Check virt-api service
kubectl get svc -n kubevirt virt-api
```

### Per-VM Components

For each VirtualMachine you create, KubeVirt spawns a dedicated pod with its own isolated stack.

## Creating a Test VM

```yaml
# vm.yml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-01
spec:
  runStrategy: Always
  template:
    metadata:
      labels:
        kubevirt.io/vm: vm-01
    spec:
      domain:
        devices:
          disks:
          - disk:
              bus: virtio
            name: containerdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            bridge: {}
          rng: {}
        machine:
          type: q35
        resources:
          requests:
            memory: 4Gi
            cpu: 2
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: quay.io/containerdisks/fedora:42
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: fedora
            chpasswd: { expire: False }
            ssh_pwauth: True
            hostname: vm-01
            ssh_authorized_keys:
              - <your-ssh-public-key>
```

Apply the VM:
```bash
kubectl apply -f vm.yml
```

## Inspecting the VM Stack

### 1. View the VM and VMI Resources

```bash
# View VirtualMachine resource (desired state)
kubectl get vm

# View VirtualMachineInstance resource (actual running instance)
kubectl get vmi

# Get detailed VM info
kubectl get vm vm-01 -o yaml

# Get VMI status including IP and guest OS info
kubectl get vmi vm-01 -o yaml | grep -A 30 "status:"
```

### 2. Find the virt-launcher Pod

Each VM gets its own pod named `virt-launcher-<vm-name>-<hash>`:

```bash
# Find the pod for your VM
kubectl get pods -l kubevirt.io/vm=vm-01

# Get detailed pod info
kubectl describe pod -l kubevirt.io/vm=vm-01

# See pod IP and node assignment
kubectl get pod -l kubevirt.io/vm=vm-01 -o wide
```

### 3. Inspect Processes Inside virt-launcher

```bash
# Get the pod name
POD=$(kubectl get pod -l kubevirt.io/vm=vm-01 -o name)

# View all processes
kubectl exec $POD -- ps aux

# View process tree
kubectl exec $POD -- ps auxf
```

You'll see:
- **PID 1**: `virt-launcher-monitor` - Watchdog/init process
- **PID ~14**: `virt-launcher` - Main KubeVirt orchestrator
- **PID ~32**: `virtqemud` - Libvirt QEMU daemon
- **PID ~33**: `virtlogd` - Libvirt logging daemon
- **PID ~93**: `qemu-kvm` - The actual VM hypervisor

### 4. Inspect the VM with virsh

The pod runs a local libvirtd instance. You can use virsh commands:

```bash
# List VMs managed by this libvirt instance
kubectl exec $POD -- virsh list --all

# Get VM info
kubectl exec $POD -- virsh dominfo default_vm-01

# View domain XML configuration
kubectl exec $POD -- virsh dumpxml default_vm-01

# Check VM resources
kubectl exec $POD -- virsh domstats default_vm-01
```

### 5. Explore the QEMU Process

```bash
# View full QEMU command line
kubectl exec $POD -- ps aux | grep qemu-kvm

# Check QEMU monitor socket
kubectl exec $POD -- ls -la /var/run/kubevirt-private/*/virt-vnc
```

The QEMU command shows:
- CPU type and count
- Memory allocation
- Disk images and their paths
- Network devices (tap/bridge)
- VNC socket for console access
- Serial console configuration

### 6. Inspect Volumes and Disks

```bash
# List pod volumes
kubectl get pod $POD -o jsonpath='{.spec.volumes[*].name}' | tr ' ' '\n'

# Check container disk location
kubectl exec $POD -- ls -lh /var/run/kubevirt/container-disks/

# Check ephemeral disk overlay
kubectl exec $POD -- ls -lh /var/run/kubevirt-ephemeral-disks/disk-data/

# View cloud-init ISO
kubectl exec $POD -- ls -lh /var/run/kubevirt-ephemeral-disks/cloud-init-data/default/vm-01/
```

### 7. Check Networking

```bash
# View network interfaces in the pod
kubectl exec $POD -- ip addr

# Check bridge configuration
kubectl exec $POD -- ip link show type bridge

# View routing table
kubectl exec $POD -- ip route

# Test connectivity from pod to VM
kubectl exec $POD -- ping -c 2 <vm-ip>
```

### 8. Access the VM Console

```bash
# Serial console access
virtctl console vm-01

# VNC access (requires port-forward or virtctl)
virtctl vnc vm-01
```

### 9. SSH into the VM

```bash
# Get the VM's IP address
kubectl get vmi vm-01 -o jsonpath='{.status.interfaces[0].ipAddress}'

# SSH directly (if using pod networking)
ssh fedora@<vm-ip>
```

### 10. Monitor VM Logs

```bash
# View VM console output
kubectl logs $POD

# View virt-launcher logs
kubectl logs $POD -c compute

# Follow logs in real-time
kubectl logs $POD -f
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                           │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ kubevirt namespace                                  │    │
│  │                                                      │    │
│  │  virt-controller (Deployment)                       │    │
│  │  virt-api (Deployment)                              │    │
│  │  virt-handler (DaemonSet - one per node)           │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ default namespace                                   │    │
│  │                                                      │    │
│  │  VirtualMachine: vm-01                              │    │
│  │  VirtualMachineInstance: vm-01                      │    │
│  │                                                      │    │
│  │  ┌──────────────────────────────────────────────┐  │    │
│  │  │ Pod: virt-launcher-vm-01-xxxxx               │  │    │
│  │  │                                               │  │    │
│  │  │  ┌─────────────────────────────────────────┐ │  │    │
│  │  │  │ Container: compute                       │ │  │    │
│  │  │  │                                          │ │  │    │
│  │  │  │  PID 1:  virt-launcher-monitor          │ │  │    │
│  │  │  │  PID 14: virt-launcher                  │ │  │    │
│  │  │  │  PID 32: virtqemud (libvirt)            │ │  │    │
│  │  │  │  PID 33: virtlogd                       │ │  │    │
│  │  │  │  PID 93: qemu-kvm ◄── Your Fedora VM    │ │  │    │
│  │  │  │                                          │ │  │    │
│  │  │  │  Volumes:                                │ │  │    │
│  │  │  │    - container-disks (Fedora image)     │ │  │    │
│  │  │  │    - ephemeral-disks (qcow2 overlay)    │ │  │    │
│  │  │  │    - cloud-init (SSH key, config)       │ │  │    │
│  │  │  │                                          │ │  │    │
│  │  │  └─────────────────────────────────────────┘ │  │    │
│  │  └──────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## How It Works: The Flow

1. **User applies VM YAML** → Kubernetes API stores the VirtualMachine resource

2. **virt-controller** sees the new VM and creates a virt-launcher pod

3. **Kubernetes scheduler** places the pod on a node (super.fe.cofront.xyz)

4. **virt-launcher-monitor** starts as PID 1 in the container

5. **virt-launcher** (PID 14) starts and:
   - Starts virtqemud and virtlogd
   - Prepares disk images from containerDisk
   - Creates cloud-init ISO with your SSH key
   - Generates libvirt domain XML
   - Tells libvirt to start the VM

6. **libvirt** launches qemu-kvm with the appropriate configuration

7. **QEMU/KVM** starts your Fedora VM with:
   - Hardware virtualization (KVM)
   - virtio devices for performance
   - Network bridged to pod's eth0
   - VNC console available

8. **virt-handler** on the node monitors the VM and reports status

9. **VirtualMachineInstance** resource is updated with runtime info (IP, guest OS)

10. **VM boots** → cloud-init runs → SSH key configured → VM ready!

## Key Concepts

### runStrategy
- `Always`: VM should always be running (auto-restart on crash)
- `Manual`: Start/stop controlled manually
- `Halted`: VM should be stopped
- `RerunOnFailure`: Restart on failure, but not on successful shutdown

### Networking Modes
- **pod**: VM shares the pod's network namespace (what we're using)
- **masquerade**: NAT-based networking, VM gets its own subnet
- **bridge**: Bridge to external network (requires Multus CNI)

## Deep Dive: How Pod Networking Works

When using `pod: {}` networking mode with a `bridge: {}` interface, KubeVirt creates a clever bridge setup inside the pod to share the pod's IP with the VM.

### The Network Stack

```
Host Network Namespace
┌──────────────────────────────────────────────┐
│  Cilium eBPF (TC hooks on veth host side)   │
│      ↓                                       │
│  lxcXXX (host side of veth pair)            │
└──────────────────────────────────────────────┘
            ↓ (veth pair - virtual wire)
┌─────────────────────────────────────────────┐
│ Pod Network Namespace (virt-launcher)       │
│                                             │
│  eth0-nic (veth pair, container side)      │
│       ↓                                     │
│  k6t-eth0 (Linux bridge)                   │
│       ├─── tap0 → QEMU/VM (virtio-net)    │
│       └─── eth0-nic                        │
│                                             │
│  Pod IP: 10.100.1.105                      │
│  VM IP:  10.100.1.105 (same!)              │
└─────────────────────────────────────────────┘
```

### How to Inspect the Networking

```bash
POD=$(kubectl get pod -l kubevirt.io/vm=vm-01 -o jsonpath='{.items[0].metadata.name}')

# 1. View all network interfaces in the pod
kubectl exec $POD -- ip addr
# Shows:
#   eth0-nic@if52: veth pair connected to Cilium (host side)
#   k6t-eth0: Linux bridge created by KubeVirt
#   tap0: TAP device connected to QEMU VM
#   eth0: Original pod interface (now DOWN)

# 2. See the bridge configuration
kubectl exec $POD -- ip link show master k6t-eth0
# Shows both tap0 and eth0-nic are attached to the bridge

# 3. View bridge details
kubectl exec $POD -- bridge link
# Shows:
#   51: eth0-nic - forwarding to Cilium
#   3: tap0 - forwarding to VM

# 4. Check what interface the VM sees
kubectl exec $POD -- virsh domiflist default_vm-01
# Shows: tap0 device with MAC 4a:5d:6c:c5:ad:01

# 5. Verify VM and pod share the same IP
kubectl get pod -l kubevirt.io/vm=vm-01 -o jsonpath='{.status.podIP}'
kubectl get vmi vm-01 -o jsonpath='{.status.interfaces[0].ipAddress}'
# Both show: 10.100.1.105

# 6. Check the VMI network info
kubectl get vmi vm-01 -o jsonpath='{.status.interfaces}' | jq .
# Shows:
#   interfaceName: enp1s0 (inside VM)
#   ipAddress: 10.100.1.105
#   podInterfaceName: eth0
#   mac: 4a:5d:6c:c5:ad:01
```

### The Setup Process

1. **Cilium CNI** creates the pod network namespace and a veth pair:
   - Creates `lxcXXX` (host side) and `eth0` (pod side)
   - Attaches eBPF programs to TC ingress/egress hooks on the veth
   - Uses VXLAN tunneling (tunnel mode) for pod-to-pod communication

2. **virt-launcher** starts and:
   - Renames `eth0` to `eth0-nic`
   - Creates a Linux bridge called `k6t-eth0`
   - Attaches `eth0-nic` to the bridge
   - Creates a TAP device `tap0`
   - Attaches `tap0` to the bridge
   - Enables IP forwarding in the pod

3. **QEMU** starts with:
   - virtio-net device connected to `tap0`
   - MAC address `4a:5d:6c:c5:ad:01`
   - Traffic flows: VM ↔ tap0 ↔ k6t-eth0 bridge ↔ eth0-nic (veth) ↔ Cilium eBPF

4. **Inside the VM**:
   - Network interface appears as `enp1s0` (virtio-net)
   - Gets IP via cloud-init (same as pod IP)
   - Sends packets out tap0
   - Packets are bridged to eth0-nic
   - eBPF programs on veth handle routing/policy

### Why This Works

The bridge acts as a **Layer 2 switch** inside the pod:
- The VM and the pod's network interface are on the same bridge
- They share the same IP address (10.100.1.105)
- Both can send/receive packets
- From outside, it looks like a single endpoint

This is different from masquerade mode where:
- VM would get its own subnet (e.g., 10.0.2.2)
- NAT would translate VM IP ↔ Pod IP
- More overhead but better isolation

### Verification Commands

```bash
# Check IP forwarding is enabled
kubectl exec $POD -- cat /proc/sys/net/ipv4/ip_forward
# Should show: 1

# Test connectivity from pod to external network
kubectl exec $POD -- ping -c 2 8.8.8.8

# SSH into the VM (since it shares the pod IP)
VM_IP=$(kubectl get vmi vm-01 -o jsonpath='{.status.interfaces[0].ipAddress}')
ssh fedora@$VM_IP

# Inside VM, check the interface
# (via virtctl console or SSH)
ip addr show enp1s0
# Shows: 10.100.1.105/32
```

### Traffic Flow Example

When you SSH to the VM:

1. **Client** → `ssh 10.100.1.105:22`
2. **Cilium eBPF** (TC hook on host veth) processes packet, checks policy
3. **Veth pair** forwards to pod's `eth0-nic`
4. **Bridge k6t-eth0** (inside pod) forwards to `tap0`
5. **QEMU/KVM** receives on VM's virtio-net interface
6. **VM OS (Fedora)** sees packet on `enp1s0`
7. **sshd** in VM responds
8. **Reverse path**: enp1s0 → tap0 → k6t-eth0 → eth0-nic → veth → Cilium eBPF → Client

The VM and pod are **network siblings** on the same bridge!

### Cilium's Role

Your cluster uses Cilium in **veth datapath mode** with:
- **Datapath**: veth pairs with eBPF programs attached to TC hooks
- **Routing**: VXLAN tunnel mode for pod-to-pod communication
- **Policy enforcement**: eBPF programs on veth handle L3/L4 filtering

Check your Cilium configuration:
```bash
kubectl get cm -n kube-system cilium-config -o yaml | grep -E "datapath-mode|routing-mode|tunnel"
# Shows:
#   datapath-mode: veth
#   routing-mode: tunnel
#   tunnel-protocol: vxlan
```

The eBPF programs run at the TC (Traffic Control) layer, processing packets as they enter/exit the pod via the veth pair. This is more efficient than traditional iptables-based CNIs.

### What is TC (Traffic Control)?

**TC is the Linux kernel's traffic management subsystem**, controlled by the `tc` command. It traditionally handles:
- QoS (Quality of Service)
- Traffic shaping and rate limiting
- Packet filtering and classification

Cilium leverages TC's **ingress/egress hooks** to attach eBPF programs:

```bash
# Conceptually, Cilium does this on the HOST side of each veth pair:
tc qdisc add dev lxcXXX clsact                           # Enable TC hooks
tc filter add dev lxcXXX ingress bpf da obj cilium.o    # Attach eBPF to ingress
tc filter add dev lxcXXX egress bpf da obj cilium.o     # Attach eBPF to egress
```

**TC Hook Terminology:**
- **TC ingress** = Packets FROM container (leaving pod)
- **TC egress** = Packets TO container (entering pod)

**Why TC over alternatives?**
- **XDP (eXpress Data Path)**: Too early in packet pipeline, limited packet context
- **iptables/netfilter**: Slow, not programmable, uses old kernel infrastructure
- **TC**: Perfect balance - full packet access, can modify packets, extremely fast

To see eBPF programs on TC (requires host access):
```bash
# On the host node
tc filter show dev lxcXXX ingress
# Shows: filter protocol all pref 1 bpf chain 0 handle 0x1 cilium.o:[from-container]
```

### Cilium Routing Modes

Your cluster currently uses **tunnel mode (VXLAN)**, but Cilium supports multiple routing options:

#### 1. Tunnel Mode (Current - VXLAN or Geneve)
```yaml
routing-mode: tunnel
tunnel-protocol: vxlan  # or geneve
```
- **How it works**: Encapsulates pod traffic in VXLAN/Geneve tunnels
- **Pros**: Works anywhere, no network infrastructure changes needed
- **Cons**: Overhead from encapsulation, harder to debug
- **Use case**: Default for most deployments, cloud environments

#### 2. Native Routing (Direct L3 Routing)
```yaml
routing-mode: native
ipv4-native-routing-cidr: 10.0.0.0/8
```
- **How it works**: Routes pod IPs directly using Linux routing tables or BGP
- **Pros**: No encapsulation overhead, simpler packet flow, better performance
- **Cons**: Requires network fabric to route pod CIDRs, or BGP setup
- **Use case**: Bare metal with BGP, or networks that can route pod subnets

**To enable native routing:**
```bash
# Update Cilium config
kubectl patch cm -n kube-system cilium-config --type merge -p '{"data":{"routing-mode":"native","tunnel-protocol":"disabled"}}'

# Restart Cilium
kubectl rollout restart daemonset -n kube-system cilium
```

#### 3. Direct Routing (Native + BGP)
```yaml
routing-mode: native
enable-bgp-control-plane: true
```
- **How it works**: Uses Cilium's BGP implementation to advertise pod CIDRs
- **Pros**: Full L3 routing, integrates with datacenter networks
- **Cons**: Requires BGP configuration
- **Use case**: Bare metal clusters, on-prem datacenters

Your cluster already has BGP enabled! Check it:
```bash
kubectl get cm -n kube-system cilium-config -o yaml | grep bgp
# Shows: bgp-control-plane-enabled: "true"
```

#### 4. Host Routing (ENI/Azure mode)
- **For cloud providers**: AWS ENI, Azure IPAM
- **How it works**: Uses cloud provider's native networking
- **Use case**: Cloud-managed Kubernetes (EKS, AKS)

### Switching to Native Routing (L3)

To switch from tunnel to native routing:

```bash
# 1. Check current settings
kubectl get cm -n kube-system cilium-config -o yaml | grep -E "routing-mode|tunnel|bgp"

# 2. Update to native routing with BGP
kubectl patch cm -n kube-system cilium-config --type merge -p '{
  "data": {
    "routing-mode": "native",
    "tunnel-protocol": "disabled",
    "ipv4-native-routing-cidr": "10.100.0.0/16",
    "enable-ipv4": "true"
  }
}'

# 3. Restart Cilium pods
kubectl rollout restart daemonset -n kube-system cilium

# 4. Verify
kubectl exec -n kube-system ds/cilium -- cilium status | grep Routing
```

**Requirements for native routing:**
- Network must be able to route pod CIDR (10.100.0.0/16)
- Either:
  - Configure static routes on your network fabric, OR
  - Use Cilium's BGP to advertise routes to your router

Since you have `bgpControlPlane.enabled=true`, you can configure BGP peering:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering
spec:
  nodeSelector:
    matchLabels:
      bgp: enabled
  virtualRouters:
  - localASN: 64512
    exportPodCIDR: true
    neighbors:
    - peerAddress: 10.254.254.1/32  # Your gateway
      peerASN: 64513
```

### Performance Comparison

**Tunnel (VXLAN) Mode:**
- ✓ Works everywhere
- ✓ No network changes needed
- ✗ ~5-10% overhead from encapsulation
- ✗ MTU considerations (need to account for VXLAN header)

**Native Routing Mode:**
- ✓ No encapsulation overhead
- ✓ Simpler troubleshooting (wireshark shows real IPs)
- ✓ Better throughput (~10-20% improvement)
- ✗ Requires network fabric configuration
- ✗ May need BGP setup

For your homelab with BGP already enabled, **native routing with BGP** would be the best choice for performance!

**Reference**: [Cilium Routing Documentation](https://docs.cilium.io/en/stable/network/concepts/routing/)

**Reference**: [Cilium eBPF Datapath Documentation](https://docs.cilium.io/en/stable/network/ebpf/intro/)

### Disk Types
- **containerDisk**: Ephemeral disk from container image
- **persistentVolumeClaim**: Persistent disk from PVC
- **dataVolume**: KubeVirt DataVolume (wraps PVC with CDI)
- **cloudInitNoCloud**: Cloud-init configuration

### Storage Behavior
With `containerDisk` + ephemeral storage:
- Base image is read-only
- A qcow2 overlay is created for writes
- Changes are lost when the pod restarts
- For persistence, use PVCs instead

## Troubleshooting Commands

```bash
# Check if VM is running
kubectl get vm,vmi

# View VM events
kubectl describe vm vm-01

# Check pod events
kubectl describe pod -l kubevirt.io/vm=vm-01

# View virt-handler logs (node-level issues)
kubectl logs -n kubevirt -l kubevirt.io=virt-handler --tail=100

# Check libvirt logs inside the pod
kubectl exec $POD -- cat /var/log/libvirt/qemu/default_vm-01.log

# View QEMU monitor commands available
kubectl exec $POD -- virsh qemu-monitor-command default_vm-01 --hmp info status
```

## Cleanup

```bash
# Delete the VM (will also delete VMI and pod)
kubectl delete vm vm-01

# Force delete if stuck
kubectl delete vm vm-01 --force --grace-period=0

# Remove finalizers if really stuck
kubectl patch vm vm-01 -p '{"metadata":{"finalizers":[]}}' --type=merge
```

## References

- Official KubeVirt Architecture: https://kubevirt.io/user-guide/architecture/
- KubeVirt User Guide: https://kubevirt.io/user-guide/
- Debugging the Virt Stack: https://kubevirt.io/user-guide/debug_virt_stack/
- GitHub Repository: https://github.com/kubevirt/kubevirt
