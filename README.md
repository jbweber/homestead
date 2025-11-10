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
- `just setup-hypervisor <host>` — Configure a hypervisor host (installs libvirt, foundry, etc.).
- `just setup-baremetal <host>` — Configure a baremetal host.

### VM Management (Foundry-based)
- `just create-vm <host> <vm>` — Create a VM using foundry on the specified host.
- `just destroy-vm <host> <vm>` — Destroy a VM using foundry on the specified host.
- `just list-vms <host>` — List all VMs on the specified host.

**Example usage:**
```sh
just setup-hypervisor clutch.cofront.xyz
just create-vm clutch.cofront.xyz br250-vm101
just list-vms clutch.cofront.xyz
just destroy-vm clutch.cofront.xyz br250-vm101
```

### VM Configuration Format

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

## Kubernetes

