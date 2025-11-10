# Homestead

This is a project used to keep configuration for my home lab environment.

## Ansible Coding Conventions

When writing Ansible code in this project:
- Use single quotes for string literals (e.g., 'example')
- Use double quotes for variable expansions (e.g., "{{ variable }}")
- Exceptions may occur if required by Ansible syntax, but follow this convention whenever possible.

## Ansible Debugging

### Debugging Tasks with `no_log: true`

When Ansible roles or tasks use `no_log: true` to hide sensitive output, you can still see the output for debugging purposes:

**Method**: Use the `ANSIBLE_DEBUG=1` environment variable combined with high verbosity:

```bash
ANSIBLE_DEBUG=1 ansible-playbook -i inventory/hosts playbook.yml -vvvv
```

This will show:
- Detailed SSH connection information
- Full command execution details
- Error messages that would normally be censored by `no_log`
- Python tracebacks and module errors

**Note**: The output from `-vvvv` can be very verbose. You may want to pipe it through `grep` or redirect to a file for easier analysis.

**Example with grep:**
```bash
ANSIBLE_DEBUG=1 ansible-playbook -i inventory/hosts playbook.yml -vvvv 2>&1 | grep -A 20 "task name"
```

## Hypervisor Management with Justfile

This project uses a `justfile` to automate common hypervisor management tasks. To use these commands, run them from the project root:

### Hypervisor Setup
- `just update-ansible` — Install/update Ansible collections and roles from `requirements.yml`.
- `just setup-hypervisor <hypervisor>` — Configure a hypervisor host (installs libvirt, foundry, etc.).
- `just setup-baremetal-hypervisor <host>` — Configure a baremetal hypervisor.

### VM Management (Foundry-based - NEW!)
- `just create-baremetal-vm <host> <vm>` — Create a VM using foundry on baremetal host.
- `just destroy-baremetal-vm <host> <vm>` — Destroy a VM using foundry on baremetal host.

### VM Management (Legacy - Ansible-based)
- `just list-hypervisors` — List all hypervisor hosts defined in your inventory.
- `just list-vms <hypervisor>` — Show VMs defined in inventory and running on the specified hypervisor.
- `just create-vm <hypervisor> <vm>` — Create a VM on the specified hypervisor (uses libvirt-create role).
- `just destroy-vm <hypervisor> <vm>` — Destroy a VM on the specified hypervisor (uses libvirt-destroy role).
- `just refresh-images` — Download/update VM base images on all hypervisors.

**Example usage (foundry-based):**
```sh
just setup-baremetal-hypervisor clutch.cofront.xyz
just create-baremetal-vm clutch.cofront.xyz br250-vm101
just destroy-baremetal-vm clutch.cofront.xyz br250-vm101
```

**Example usage (legacy):**
```sh
just list-hypervisors
just list-vms gravity.fe.cofront.xyz
just create-vm gravity.fe.cofront.xyz vm-101
just destroy-vm gravity.fe.cofront.xyz vm-101
```

### VM Configuration Formats

#### Foundry v1alpha1 Format (NEW!)

VMs managed by foundry use a Kubernetes-style declarative format. VM specs are stored in:
```
inventory/<inventory>/host_vars/<hypervisor>/vms/<vm-name>.yml
```

**Example VM spec:**
```yaml
apiVersion: foundry.cofront.xyz/v1alpha1
kind: VirtualMachine
metadata:
  name: br250-vm101
  labels:
    environment: development
spec:
  vcpus: 2
  memoryGiB: 4
  bootDisk:
    sizeGB: 20
    image: fedora-43-ext4.qcow2
  networkInterfaces:
    - ip: 10.250.250.101/24
      gateway: 10.250.250.1
      dnsServers: [8.8.8.8, 1.1.1.1]
      bridge: br250
      defaultRoute: true
  cloudInit:
    fqdn: br250-vm101.example.com
    sshAuthorizedKeys:
      - "{{ vault_hypervisor_ssh_keys | first }}"
```

See [foundry/DESIGN.md](../foundry/DESIGN.md) for complete v1alpha1 specification.

#### Legacy hypervisor_machines Format

All VMs in the hypervisors inventory use a single, unified configuration format defined in `hypervisor_machines`:

```yaml
hypervisor_machines:
  my-vm:
    name: 'my-vm'
    fqdn: 'my-vm.example.com'
    ip: '10.20.30.40/32'           # IP with CIDR notation
    gateway: '169.254.0.1'         # Gateway (required)
    dns_servers: ['8.8.8.8']       # DNS servers (required)

    # Libvirt attachment (optional)
    network_source: 'vm1'          # Omit for ethernet/BGP mode
    network_type: 'bridge'         # bridge or network

    # Hardware
    vcpus: 2
    memory_gib: 4
    boot_disk_size_gb: 20
    image_template: 'fedora-42-cloud'
```

**Key features:**
- MAC addresses are automatically calculated from IP: `be:ef:xx:xx:xx:xx`
- Network config delivered via cloud-init ISO (no DHCP needed)
- `network_source` determines attachment type:
  - **Omitted**: Ethernet interface (BGP/routing mode)
  - **Defined**: Bridge/network attachment (standard mode)

**Examples:**

BGP/Ethernet mode (no network_source):
```yaml
bgp-vm:
  ip: '10.55.22.22/32'
  gateway: '169.254.0.1'
  # No network_source = ethernet interface
```

Bridge mode (with network_source):
```yaml
bridge-vm:
  ip: '10.100.102.101/24'
  gateway: '10.100.102.1'
  network_source: 'vm1'
  network_type: 'bridge'
```

### Cloud-init Configuration

All VMs now use cloud-init ISOs for initial configuration, which are automatically generated and attached. You can configure:

- `ssh_keys`: List of SSH public keys for root access (can be set per-VM or globally via `hypervisor_ssh_keys`)
- `root_password_hash`: Hashed password for root user (optional, can be set per-VM or globally via `cloudinit_root_password_hash`)
- `ssh_pwauth`: Enable/disable password authentication (default: false)
- `static_ip`: Static IP configuration for standard mode (optional)
- `gateway`: Gateway IP address
- `dns_servers`: List of DNS servers (defaults to 8.8.8.8 and 1.1.1.1)

#### Global SSH Keys and Passwords

Instead of defining SSH keys and passwords for each VM, you can set them globally at the hypervisor level in your host_vars:

```yaml
# In inventory/hypervisors/host_vars/<hypervisor>.yml
hypervisor_ssh_keys: "{{ vault_hypervisor_ssh_keys }}"
cloudinit_root_password_hash: "{{ vault_root_password_hash }}"
```

These will be used as defaults for all VMs on that hypervisor. Individual VMs can still override them by specifying their own `ssh_keys` or `root_password_hash`.

Make sure you have Ansible and the required collections installed. For advanced usage, see the playbooks in `playbooks/hypervisor/`.

## Kubernetes

