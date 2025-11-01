# libvirt-create Role

This role creates and configures KVM/libvirt virtual machines with unified network configuration.

## Features

- **Unified configuration**: Single format for all VMs, regardless of network mode
- **Automatic MAC calculation**: MAC addresses derived from IP (be:ef:xx:xx:xx:xx)
- **Cloud-init ISOs**: All network config delivered via cloud-init
- **Disk management**: Creates boot disk and optional data disks with space validation
- **Image templates**: Uses predefined VM image templates or custom images
- **Flexible networking**: Supports both BGP routing (ethernet) and bridge/network attachments

## Requirements

- QEMU/KVM installed on the host
- `genisoimage` package for creating cloud-init ISOs
- `community.libvirt` Ansible collection
- Base VM images available on the hypervisor

## Role Variables

### Required Variables

- `libvirt_create_machine`: Dictionary containing VM configuration (see examples below)

### Optional Variables (set in defaults/main.yml)

```yaml
qemu_emulator: '/usr/bin/qemu-kvm'         # Path to QEMU emulator
vm_images_base_path: '/var/lib/libvirt/images'  # Base path for VM images
vm_images: {}                               # VM image repository
vm_default_image: 'fedora-42-cloud'       # Default image template
skip_cloudinit: false                       # Skip cloud-init generation (default: false)
```

## Unified VM Configuration

All VMs use the same configuration format with a `network_interfaces` list that supports both single and multiple network interfaces.

### Configuration Format

```yaml
libvirt_create_machine:
  name: 'my-vm'                      # VM name (required)
  fqdn: 'my-vm.example.com'          # Fully qualified domain name (optional)

  # Network interfaces (required)
  network_interfaces:
    - ip: '10.20.30.40/32'           # IP with CIDR (required)
      gateway: '169.254.0.1'         # Gateway (required)
      dns_servers:                   # DNS servers (required)
        - '8.8.8.8'
        - '1.1.1.1'
      default_route: true            # Set default route (required for primary interface)
      network_source: 'vm1'          # Bridge or network name (optional - omit for ethernet/BGP mode)
      network_type: 'bridge'         # 'bridge' or 'network' (default: bridge)

  # Hardware
  vcpus: 4
  memory_gib: 8
  boot_disk_size_gb: 50
  cpu_mode: 'host-passthrough'       # Optional

  # Image
  image_template: 'fedora-42-cloud'

  # Cloud-init
  ssh_keys:                          # Optional, falls back to hypervisor_ssh_keys
    - "ssh-ed25519 AAAA..."
```

### Network Mode Examples

**BGP/Ethernet Mode** (no bridge attachment):
```yaml
my-bgp-vm:
  name: 'bgp-vm'
  network_interfaces:
    - ip: '10.55.22.22/32'
      gateway: '169.254.0.1'
      dns_servers: ['8.8.8.8', '1.1.1.1']
      default_route: true
  vcpus: 2
  memory_gib: 4
  boot_disk_size_gb: 20
  image_template: 'fedora-42-cloud'
```
- Creates ethernet interface
- MAC: `be:ef:0a:37:16:16` (auto-calculated from IP)
- Uses on-link routing for off-subnet gateway

**Bridge Mode** (with bridge attachment):
```yaml
my-bridge-vm:
  name: 'bridge-vm'
  network_interfaces:
    - ip: '10.100.102.101/24'
      gateway: '10.100.102.1'
      dns_servers: ['10.100.102.1']
      network_source: 'vm1'
      network_type: 'bridge'
      default_route: true
  vcpus: 2
  memory_gib: 4
  boot_disk_size_gb: 20
  image_template: 'fedora-42-cloud'
```
- Creates bridge interface attached to 'vm1'
- MAC: `be:ef:0a:64:66:65` (auto-calculated from IP)
- Normal routing within /24 subnet

**Multiple Interfaces** (dual-homed VM):
```yaml
my-dual-vm:
  name: 'dual-vm'
  network_interfaces:
    - ip: '10.254.254.10/24'
      gateway: '10.254.254.1'
      dns_servers: ['8.8.8.8', '1.1.1.1']
      network_source: 'br254'
      network_type: 'bridge'
      default_route: true
    - ip: '10.255.255.10/24'
      gateway: '10.255.255.1'
      dns_servers: ['8.8.8.8']
      network_source: 'br255'
      network_type: 'bridge'
      default_route: false
  vcpus: 4
  memory_gib: 8
  boot_disk_size_gb: 40
  image_template: 'fedora-43-cloud'
```
- Creates two bridge interfaces
- First interface has default route
- Second interface configured without default route
- Each interface gets its own MAC address calculated from its IP

## Common Configuration Options

All VMs support these configuration options:

### VM Hardware
- `name` (required): VM name
- `vcpus` (required): Number of virtual CPUs
- `memory_gib` (required): Memory in GiB
- `boot_disk_size_gb` (required): Boot disk size in GB
- `cpu_mode` (optional): CPU mode (default: 'host-model')
- `vnc_port` (optional): VNC port for console access
- `vnc_listen` (optional): VNC listen address (default: '127.0.0.1')

### Image Configuration
- `image_template` (optional): Named image template from `vm_images`
- `image_path` (optional): Direct path to base image (if not using template)
- `image_format` (optional): Image format (if not using template)

### Data Disks
```yaml
data_disks:
  - device: vdb
    size_gb: 100
  - device: vdc
    size_gb: 200
```

### Cloud-init Configuration
- `skip_cloudinit`: Skip cloud-init generation for this VM (default: false, uses global `skip_cloudinit` setting)
- `ssh_keys`: List of SSH public keys for root user (falls back to `hypervisor_ssh_keys` if not defined)
- `root_password_hash`: Hashed root password (optional, falls back to `cloudinit_root_password_hash` if not defined)
- `ssh_pwauth`: Enable password authentication (default: false)
- `fqdn`: Fully qualified domain name (defaults to `name`)
- `console_autologin`: Enable autologin on serial console as 'fedora' user for debugging (default: false)

**Note:** SSH keys and root password can be defined either per-VM or globally at the hypervisor level:
- Per-VM: `libvirt_create_machine.ssh_keys` and `libvirt_create_machine.root_password_hash`
- Global: `hypervisor_ssh_keys` and `cloudinit_root_password_hash` (applies to all VMs on the hypervisor)

## Example Playbook

```yaml
---
- name: Create VM
  hosts: hypervisor
  become: true
  tasks:
    - name: Create VM using libvirt-create role
      ansible.builtin.include_role:
        name: libvirt-create
      vars:
        libvirt_create_machine:
          name: my-vm
          ip: 10.100.0.50
          vcpus: 4
          memory_gib: 8
          boot_disk_size_gb: 40
          image_template: fedora-42-cloud
          ssh_keys:
            - "{{ lookup('file', '~/.ssh/id_ed25519.pub') }}"
```

### Example: VM Without Cloud-init

For VMs that don't support cloud-init or have pre-configured images:

```yaml
---
- name: Create VM without cloud-init
  hosts: hypervisor
  become: true
  tasks:
    - name: Create VM using libvirt-create role
      ansible.builtin.include_role:
        name: libvirt-create
      vars:
        libvirt_create_machine:
          name: my-custom-vm
          ip: 10.100.0.51
          gateway: 10.100.0.1
          dns_servers: ['8.8.8.8']
          vcpus: 4
          memory_gib: 8
          boot_disk_size_gb: 40
          image_template: custom-preconfigured-image
          skip_cloudinit: true  # Skip cloud-init generation
```

## How It Works

1. **Validation Phase**
   - Validates QEMU emulator exists
   - Detects networking mode
   - Validates VM configuration
   - Checks base image exists
   - Validates sufficient disk space

2. **Disk Creation Phase**
   - Creates VM directory
   - Creates boot disk as qcow2 snapshot from base image
   - Creates any additional data disks
   - Sets proper ownership and permissions

3. **Cloud-init Phase** (skipped if `skip_cloudinit` is true)
   - Generates user-data (SSH keys, passwords, hostname)
   - Generates meta-data (instance ID, hostname)
   - Generates network-config (networking based on mode)
   - Creates cloud-init ISO
   - Attaches ISO as CDROM device

4. **VM Creation Phase**
   - Generates libvirt XML definition
   - Defines VM in libvirt
   - Starts VM with autostart enabled

## Templates

The role includes these templates:

- `kvm.xml.j2`: Libvirt domain XML with conditional networking
- `user-data.j2`: Cloud-init user data
- `meta-data.j2`: Cloud-init metadata
- `network-config.j2`: Cloud-init network configuration (mode-aware)

## Notes

- VMs are created in `/var/lib/libvirt/images/<vm-name>/`
- Cloud-init ISOs are named `<vm-name>-cloudinit.iso`
- The role is idempotent - running it multiple times won't recreate existing VMs
- Boot disks use qcow2 snapshots for efficient storage
- BGP mode requires MAC addresses starting with `be:ef:` for proper routing
