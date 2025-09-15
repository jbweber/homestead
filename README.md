# Homestead

This is a project used to keep configuration for my home lab environment.

## Ansible Coding Conventions

When writing Ansible code in this project:
- Use single quotes for string literals (e.g., 'example')
- Use double quotes for variable expansions (e.g., "{{ variable }}")
- Exceptions may occur if required by Ansible syntax, but follow this convention whenever possible.

## Hypervisor Management with Justfile

This project uses a `justfile` to automate common hypervisor management tasks. To use these commands, run them from the project root:

- `just update-ansible` — Install/update Ansible collections and roles from `requirements.yml`.
- `just list-hypervisors` — List all hypervisor hosts defined in your inventory.
- `just list-vms <hypervisor>` — Show VMs defined in inventory and running on the specified hypervisor.
- `just create-vm <hypervisor> <vm>` — Create a VM on the specified hypervisor.
- `just destroy-vm <hypervisor> <vm>` — Destroy a VM on the specified hypervisor.

**Example usage:**
```sh
just list-hypervisors
just list-vms gravity.fe.cofront.xyz
just create-vm gravity.fe.cofront.xyz vm-101
just destroy-vm gravity.fe.cofront.xyz vm-101
```

Make sure you have Ansible and the required collections installed. For advanced usage, see the playbooks in `playbooks/hypervisor/`.

## Kubernetes

