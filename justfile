# Homestead Justfile
#
# This file defines common automation tasks for managing your home lab infrastructure.
# Run `just` or `just help` to see available commands.

update-ansible:
    ansible-galaxy install -r requirements.yml --force

list-hypervisors:
    ansible-playbook -i inventory/hypervisors --list-hosts playbooks/hypervisor/setup.yml

list-vms hypervisor:
    ansible-playbook -i inventory/hypervisors playbooks/hypervisor/list-vms.yml --limit {{hypervisor}}

create-vm hypervisor vm:
    ansible-playbook -i inventory/hypervisors playbooks/hypervisor/create.yml --limit {{hypervisor}} -e machine_name={{vm}}

destroy-vm hypervisor vm:
    ansible-playbook -i inventory/hypervisors playbooks/hypervisor/destroy.yml --limit {{hypervisor}} -e machine_name={{vm}}

refresh-images:
    ansible-playbook -i inventory/hypervisors playbooks/hypervisor/refresh-images.yml

setup-hypervisor hypervisor:
    ansible-playbook -i inventory/hypervisors playbooks/hypervisor/setup.yml --limit {{hypervisor}}

setup-hypervisor-network hypervisor:
    ansible-playbook -i inventory/hypervisors playbooks/hypervisor/setup.yml --limit {{hypervisor}} --tags systemd-networkd

setup-kubernetes-node cluster:
    ansible-playbook -i inventory/kubernetes-{{cluster}} playbooks/kubernetes/node-setup.yml

setup-baremetal host:
    ansible-playbook -i inventory/baremetal playbooks/baremetal/setup.yml --limit {{host}}

setup-baremetal-hypervisor host:
    ansible-playbook -i inventory/baremetal playbooks/baremetal/setup-hypervisor.yml --limit {{host}}

create-baremetal-vm host vm:
    ansible-playbook -i inventory/baremetal playbooks/baremetal/create-vm.yml --limit {{host}} -e vm_name={{vm}}

destroy-baremetal-vm host vm:
    ansible-playbook -i inventory/baremetal playbooks/baremetal/destroy-vm.yml --limit {{host}} -e vm_name={{vm}}