# Homestead Justfile
#
# This file defines common automation tasks for managing your home lab infrastructure.
# Run `just` or `just help` to see available commands.

update-ansible:
    ansible-galaxy install -r requirements.yml

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