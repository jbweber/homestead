# Homestead Justfile
#
# This file defines common automation tasks for managing your home lab infrastructure.
# Run `just` or `just help` to see available commands.

# Update Ansible collections and roles
update-ansible:
    ansible-galaxy install -r requirements.yml --force

# Hypervisor Setup
setup-hypervisor host:
    ansible-playbook -i inventory/baremetal playbooks/baremetal/setup-hypervisor.yml --limit {{host}}

# VM Management (Foundry-based)
create-vm host vm:
    ansible-playbook -i inventory/baremetal playbooks/baremetal/create-vm.yml --limit {{host}} -e vm_name={{vm}}

destroy-vm host vm:
    ansible-playbook -i inventory/baremetal playbooks/baremetal/destroy-vm.yml --limit {{host}} -e vm_name={{vm}}

list-vms host:
    ssh {{host}} 'foundry list'

# Kubernetes Setup
setup-kubernetes-node cluster:
    ansible-playbook -i inventory/kubernetes-{{cluster}} playbooks/kubernetes/node-setup.yml

# Baremetal Setup
setup-baremetal host:
    ansible-playbook -i inventory/baremetal playbooks/baremetal/setup.yml --limit {{host}}
