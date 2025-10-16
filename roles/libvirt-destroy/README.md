# libvirt-destroy Role

This role safely destroys KVM/libvirt virtual machines, including all associated resources.

## Features

- **Graceful shutdown**: Attempts to shut down VM before destroying
- **Complete cleanup**: Removes VM definition and all disk files
- **Safe operation**: Checks if VM exists before attempting destruction
- **Idempotent**: Can be run multiple times safely

## Requirements

- `community.libvirt` Ansible collection
- libvirt/KVM running on the host

## Role Variables

### Required Variables

- `libvirt_destroy_machine`: Dictionary containing VM configuration with at least:
  - `name`: Name of the VM to destroy

### Example

```yaml
libvirt_destroy_machine:
  name: my-vm
```

## How It Works

1. **Check Phase**
   - Checks if VM exists in libvirt

2. **Shutdown Phase**
   - Attempts graceful shutdown of the VM
   - Waits 5 seconds for shutdown to complete

3. **Cleanup Phase**
   - Undefines the VM from libvirt (removes definition)
   - Removes NVRAM files if present
   - Deletes VM directory and all contents from `/var/lib/libvirt/images/<vm-name>/`

## Example Playbook

```yaml
---
- name: Destroy VM
  hosts: hypervisor
  become: true
  tasks:
    - name: Destroy VM using libvirt-destroy role
      ansible.builtin.include_role:
        name: libvirt-destroy
      vars:
        libvirt_destroy_machine:
          name: my-vm
```

## What Gets Deleted

When a VM is destroyed, the following are removed:

- VM libvirt definition
- NVRAM/UEFI variables
- Boot disk (qcow2)
- All data disks
- Cloud-init ISO
- VM directory (`/var/lib/libvirt/images/<vm-name>/`)

## Notes

- The role is idempotent - running it on a non-existent VM will not fail
- Shutdown failures are ignored to ensure cleanup proceeds
- All operations run only if VM exists
- Works for both BGP and Standard mode VMs (no mode detection needed)
