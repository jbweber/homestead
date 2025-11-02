# Ansible Best Practices for Homestead

This document outlines the conventions and best practices for writing Ansible code in the Homestead project.

## Table of Contents

- [Role Structure](#role-structure)
- [Variable Naming and Scope](#variable-naming-and-scope)
- [Playbook Organization](#playbook-organization)
- [Tasks and Handlers](#tasks-and-handlers)
- [Inventory Structure](#inventory-structure)
- [Tags](#tags)
- [Idempotency](#idempotency)

## Role Structure

### Directory Layout

Roles should follow the standard Ansible directory structure:

```
roles/
└── role_name/
    ├── tasks/
    │   └── main.yml
    ├── handlers/
    │   └── main.yml
    ├── defaults/
    │   └── main.yml
    ├── vars/
    │   └── main.yml
    ├── meta/
    │   └── main.yml
    ├── templates/
    ├── files/
    └── README.md (optional but recommended)
```

### Role Naming

- Use **snake_case** for role names (e.g., `homestead_base`, `vm_image_download`)
- Role names should be descriptive and indicate their purpose
- Prefix project-specific roles with `homestead_` when appropriate

### When to Create a Role

Create a role when:
- Tasks are reused across multiple playbooks
- A logical grouping of related tasks exists (e.g., hypervisor configuration, network setup)
- Configuration is complex enough to benefit from organization

Don't create a role when:
- Tasks are used in only one place
- The configuration is trivial (1-2 tasks)

## Variable Naming and Scope

### Variable Naming Conventions

1. **Role Variables**: Prefix with the role name to avoid conflicts
   ```yaml
   # Good
   hypervisor_enable_nested_virtualization: true
   libvirt_packages: [...]

   # Bad (no prefix, could conflict)
   enable_nested_virtualization: true
   packages: [...]
   ```

2. **Use snake_case** for all variable names
   ```yaml
   # Good
   network_allow_restart: true
   vm_image_url: "https://..."

   # Bad
   NetworkAllowRestart: true
   vmImageURL: "https://..."
   ```

3. **Boolean variables** should be clearly named
   ```yaml
   # Good
   hypervisor_disable_firewall: false
   network_allow_restart: true

   # Bad (ambiguous)
   firewall: false
   restart: true
   ```

### Variable Scope and Precedence

Variables should be placed according to their scope (from lowest to highest precedence):

1. **Role Defaults** (`roles/*/defaults/main.yml`)
   - Default values that users are expected to override
   - Should include documentation/comments
   ```yaml
   ---
   # Enable nested virtualization support
   # When enabled, configures KVM to allow nested virtualization (VMs inside VMs)
   hypervisor_enable_nested_virtualization: false
   ```

2. **Role Vars** (`roles/*/vars/main.yml`)
   - Internal role variables that should NOT be overridden
   - Constants and derived values
   ```yaml
   ---
   # Internal variables - do not override
   __hypervisor_config_path: /etc/kvm
   __hypervisor_supported_vendors: [intel, amd]
   ```
   **Prefix internal variables with double underscore `__`**

3. **Group Vars** (`inventory/*/group_vars/`)
   - Variables that apply to all hosts in a group
   - Environment-specific configuration
   ```yaml
   # inventory/baremetal/group_vars/all/images.yml
   vm_images:
     - name: fedora40
       url: https://...
   ```

4. **Host Vars** (`inventory/*/host_vars/`)
   - Host-specific configuration
   - Use multi-file approach for complex configurations
   ```
   inventory/baremetal/host_vars/
   └── hostname.example.com/
       ├── network.yml
       ├── hypervisor.yml
       └── custom.yml
   ```

5. **Playbook Variables** (avoid when possible)
   - Only use for playbook-specific logic
   - Prefer inventory variables for configuration

### Variable Organization

For complex inventories, organize variables by category:

```
inventory/baremetal/
├── group_vars/
│   └── all/
│       ├── default.yml      # General settings
│       ├── images.yml        # VM images
│       └── vault.yml         # Secrets
└── host_vars/
    └── hostname/
        ├── network.yml       # Network configuration
        ├── hypervisor.yml    # Hypervisor settings
        └── services.yml      # Service-specific config
```

## Playbook Organization

### Playbook Structure

```yaml
---
- name: Descriptive playbook name
  hosts: target_group
  become: true
  gather_facts: true
  tasks:
    - name: Clear task description
      ansible.builtin.include_role:
        name: role_name
      tags: [tag1, tag2]
```

### Playbook Naming

- Use descriptive names: `setup-hypervisor.yml`, `deploy-vm.yml`
- Use hyphens for multi-word names (not underscores)
- Group related playbooks in subdirectories

### Task Extraction

Extract common tasks into roles rather than duplicating in playbooks:

```yaml
# Good - DRY principle
- name: Apply base configuration
  ansible.builtin.include_role:
    name: homestead_base

# Bad - duplicating tasks across playbooks
- name: Set hostname
  ansible.builtin.hostname:
    name: "{{ inventory_hostname }}"
```

## Tasks and Handlers

### Task Naming

- Use descriptive, action-oriented names
- Start with a capital letter
- Use present tense

```yaml
# Good
- name: Install libvirt packages
- name: Enable and start libvirtd service
- name: Configure bridge networking

# Bad
- name: packages
- name: libvirtd
- name: setup
```

### Module Usage

1. **Use fully qualified collection names (FQCN)**
   ```yaml
   # Good
   - name: Install packages
     ansible.builtin.dnf:
       name: libvirt
       state: present

   # Bad (deprecated short form)
   - name: Install packages
     dnf:
       name: libvirt
       state: present
   ```

2. **Prefer specific modules over shell/command**
   ```yaml
   # Good
   - name: Create directory
     ansible.builtin.file:
       path: /etc/myapp
       state: directory

   # Bad
   - name: Create directory
     ansible.builtin.shell: mkdir -p /etc/myapp
   ```

3. **Use appropriate conditionals**
   ```yaml
   # Good - check mode aware
   when: service_exists.stat.exists or not ansible_check_mode

   # Good - multiple conditions
   when:
     - hypervisor_enable_nested_virtualization | bool
     - cpu_vendor == 'intel'
   ```

### Handlers

- Name handlers clearly and consistently
- Handlers should be idempotent
- Use `listen` for common handler groups

```yaml
# handlers/main.yml
---
- name: Restart networking
  ansible.builtin.systemd:
    name: NetworkManager
    state: restarted
  listen: "restart network services"

- name: Reload network configuration
  ansible.builtin.systemd:
    name: NetworkManager
    state: reloaded
  listen: "restart network services"
```

## Inventory Structure

### Multi-Environment Support

Organize inventories by environment or purpose:

```
inventory/
├── baremetal/
│   ├── hosts
│   ├── group_vars/
│   └── host_vars/
├── hypervisors/
│   ├── hosts
│   ├── group_vars/
│   └── host_vars/
└── kubernetes-cluster/
    ├── hosts
    ├── group_vars/
    └── host_vars/
```

### Host Files

Use INI format for simple inventories:

```ini
[hypervisor]
clutch.cofront.xyz ansible_user=jweber

[webservers]
web01.example.com
web02.example.com

[database]
db01.example.com
```

Use YAML format for complex inventories with many variables.

### Multi-File Host Variables

For hosts with complex configuration, use a directory:

```
host_vars/
└── hostname.example.com/
    ├── network.yml
    ├── hypervisor.yml
    └── services.yml
```

This is preferred over a single large YAML file.

## Tags

### Tag Naming

- Use lowercase with hyphens
- Be descriptive and consistent
- Group related tasks with the same tags

```yaml
- name: Configure hypervisor
  ansible.builtin.include_role:
    name: hypervisor
  tags: [hypervisor, virtualization]

- name: Install libvirt
  ansible.builtin.include_role:
    name: libvirt
  tags: [libvirt, virtualization]
```

### Common Tags

Use these standard tags across the project:
- `network` - Networking configuration
- `virtualization` - KVM/libvirt/hypervisor setup
- `security` - Firewall, SELinux, etc.
- `packages` - Package installation
- `config` - Configuration file changes

## Idempotency

### Check Mode Support

All roles should support `--check` mode for safe testing:

```yaml
- name: Check if service exists
  ansible.builtin.stat:
    path: /usr/lib/systemd/system/myservice.service
  register: service_file

- name: Start service
  ansible.builtin.systemd:
    name: myservice
    state: started
  when: service_file.stat.exists or not ansible_check_mode
```

### State Management

- Always use `state` parameter explicitly
- Prefer declarative state over imperative commands

```yaml
# Good
- name: Ensure directory exists
  ansible.builtin.file:
    path: /etc/myapp
    state: directory

# Bad (not idempotent)
- name: Create directory
  ansible.builtin.command: mkdir /etc/myapp
```

### Systemd Unit Types

Systemd manages various unit types, each with different management requirements:

**Reference documentation:**
- [systemd.unit - Official Documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html)
- [Socket Activation for Developers](http://0pointer.de/blog/projects/socket-activation.html)
- [Understanding Systemd Units (DigitalOcean)](https://www.digitalocean.com/community/tutorials/understanding-systemd-units-and-unit-files)

**Common unit types:**

1. **Service (.service)**: Traditional daemon processes
2. **Socket (.socket)**: Socket-based activation for on-demand service startup
3. **Timer (.timer)**: Scheduled activation (like cron)
4. **Path (.path)**: File/directory change-based activation
5. **Target (.target)**: Grouping and synchronization points
6. **Slice (.slice)**: Resource control hierarchy

### Socket-Activated Services

Many modern services use **socket activation** where:
- The `.socket` unit listens on a port/socket and stays running
- The `.service` unit starts on-demand when connections arrive
- Services may auto-exit after idle timeout to save resources

**CRITICAL**: When using socket activation, **only manage the socket unit**. The service unit does **not** need to be enabled or started manually - systemd handles this automatically.

**Examples:** libvirtd (120s timeout), systemd-resolved, cups, docker (optional)

**How to identify socket-activated services:**
```bash
# Check for socket units
systemctl list-units --type=socket | grep myservice

# Check service for timeout
systemctl cat myservice.service | grep -i timeout

# Check service environment
systemctl show myservice.service | grep Environment
```

**Managing socket-activated services in Ansible:**
```yaml
# Good - Only manage the socket
- name: Enable myservice socket
  ansible.builtin.systemd:
    name: myservice.socket
    enabled: true
    state: started

# The service itself does NOT need to be enabled or managed
# It will be started automatically by systemd when connections arrive

# Bad - Managing the service directly
- name: Start service
  ansible.builtin.systemd:
    name: myservice.service
    state: started  # Will exit after timeout and show changed next run
```

**Key points:**
- **Only enable/start the socket** - don't touch the service at all
- The service doesn't need to be enabled (socket activation handles it)
- The service enablement state is irrelevant when socket activation is used
- Do NOT try to enable or start the service - it will show as "changed" when it times out
- Systemd will warn if you disable a socket-activated service (informational only)

**What happens:**
```bash
# When socket is enabled/started:
$ systemctl status myservice.socket   # active (listening)
$ systemctl status myservice.service  # inactive (dead) - THIS IS FINE

# After first connection:
$ systemctl status myservice.service  # active (running)

# After idle timeout:
$ systemctl status myservice.service  # inactive (dead) - back to idle
$ systemctl status myservice.socket   # active (listening) - still ready
```

**When to manage the service directly:**
- Service doesn't have a corresponding `.socket` unit
- You explicitly want the service running continuously (not on-demand)
- You've disabled the idle timeout

### Systemd Module Idempotency

**IMPORTANT**: The `ansible.builtin.systemd` module always reports "changed" when both `state` and `enabled` parameters are used together **for service units**, even if the service is already in the desired state.

**Note**: Socket units may not have this issue, but for consistency and clarity, the best practice is still to split the operations or test your specific case.

**Solution**: Split state management and enablement into separate tasks:

```yaml
# Good - Idempotent
- name: Start service
  ansible.builtin.systemd:
    name: myservice
    state: started

- name: Enable service
  ansible.builtin.systemd:
    name: myservice
    enabled: true

# Bad - Always shows as changed
- name: Enable and start service
  ansible.builtin.systemd:
    name: myservice
    state: started
    enabled: true
```

This applies to all systemd operations (start/stop/restart with enable/disable).

**Additional systemd best practices:**

1. **Static Units**: Template units and some system units have "static" enablement state and cannot be enabled/disabled. Attempting to disable them will always report "changed". Check the enablement state first or skip disable operations for static units.

   ```yaml
   # Good - Only look for active services to stop
   - name: Find active services
     ansible.builtin.shell: |
       systemctl list-units --type=service --state=active --no-legend | grep 'pattern' | awk '{print $1}' || true
     register: services
     changed_when: false

   - name: Stop active services
     ansible.builtin.systemd:
       name: "{{ item }}"
       state: stopped
     loop: "{{ services.stdout_lines }}"
     when: services.stdout | length > 0
   ```

2. **Check Current State**: To truly achieve idempotency, check the current service state before making changes:

   ```yaml
   - name: Get service status
     ansible.builtin.systemd:
       name: myservice
     register: service_status

   - name: Start service only if not active
     ansible.builtin.systemd:
       name: myservice
       state: started
     when:
       - service_status.status.ActiveState is defined
       - service_status.status.ActiveState != "active"
   ```

3. **Clean up failed units**: Failed systemd units remain loaded in memory. To properly clean them up:

   ```yaml
   - name: Stop service (may fail if already stopped)
     ansible.builtin.systemd:
       name: myservice
       state: stopped
     failed_when: false

   - name: Reset failed state
     ansible.builtin.command: systemctl reset-failed myservice
     changed_when: false
     failed_when: false
   ```

### Changed When

Use `changed_when` for commands that don't report changes correctly:

```yaml
- name: Check CPU vendor
  ansible.builtin.command: grep vendor_id /proc/cpuinfo
  register: cpu_info
  changed_when: false
  check_mode: false
```

## Security Best Practices

### Secrets Management

1. **Never commit secrets to git**
2. Use Ansible Vault for sensitive data
3. Store vault files in `group_vars/all/vault.yml` or `host_vars/*/vault.yml`
4. Use descriptive variable names for vault variables:
   ```yaml
   vault_database_password: "secret123"
   vault_api_token: "token456"
   ```

### Privilege Escalation

- Use `become: true` at the play level when all tasks need privileges
- Use `become: false` on specific tasks that don't need privileges
- Avoid running entire playbooks as root when not necessary

## Documentation

### Role Documentation

Each role should have a README.md with:
- Purpose and description
- Required variables
- Optional variables with defaults
- Example usage
- Dependencies

### Inline Comments

- Comment complex logic
- Explain non-obvious conditionals
- Document variable purposes in defaults

```yaml
# Enable nested virtualization for running VMs inside VMs
# This requires:
# - CPU support for nested virtualization
# - Module parameter to be set before libvirt starts
hypervisor_enable_nested_virtualization: false
```

## Testing

### Check Mode

Always test playbooks with `--check` before running:

```bash
ansible-playbook playbook.yml --check --diff
```

### Diff Mode

Use `--diff` to see what would change:

```bash
ansible-playbook playbook.yml --diff
```

### Limit Testing

Test on single hosts before running on groups:

```bash
ansible-playbook playbook.yml --limit hostname.example.com
```

## Common Patterns

### Conditional Role Inclusion

```yaml
- name: Install optional component
  ansible.builtin.include_role:
    name: optional_role
  when: enable_optional_feature | default(false) | bool
```

### OS-Specific Tasks

```yaml
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_os_family }}.yml"

- name: Install packages (RedHat)
  ansible.builtin.dnf:
    name: "{{ packages }}"
  when: ansible_os_family == 'RedHat'
```

### Loop Handling

```yaml
# Good - descriptive loop variable
- name: Create multiple directories
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: directory
    mode: "{{ item.mode }}"
  loop: "{{ directories }}"
  loop_control:
    label: "{{ item.path }}"  # Only show path in output
```

## Code Review Checklist

Before committing Ansible code, verify:

- [ ] All variables use appropriate scope and naming
- [ ] Tasks have clear, descriptive names
- [ ] FQCN used for all modules
- [ ] Playbook/role is idempotent
- [ ] Check mode is supported
- [ ] No secrets in plain text
- [ ] Appropriate tags applied
- [ ] Code follows project conventions
- [ ] Complex logic is commented
- [ ] Tested with `--check` and `--diff`
