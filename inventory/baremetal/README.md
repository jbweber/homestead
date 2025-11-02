# Baremetal Inventory

This inventory contains configuration for baremetal servers in the homestead environment.

## Structure

```
baremetal/
├── hosts                    # Inventory hosts file
├── group_vars/
│   └── all/
│       ├── default.yml      # General default variables
│       ├── images.yml       # OS image definitions
│       └── vault.yml        # Encrypted secrets
└── host_vars/
    └── clutch.cofront.xyz/  # Multi-file host-specific configuration
        ├── network.yml      # Network configuration
        └── hypervisor.yml   # Hypervisor configuration
```

## Configuration Files

### group_vars/all/

Variables in this directory apply to all hosts in the inventory.

- **default.yml**: General configuration variables that apply to all hosts
- **images.yml**: Operating system image definitions for VM deployments
- **vault.yml**: Encrypted secrets (passwords, API keys, etc.)

### host_vars/

Host-specific variables that override group variables. Each host can use either a single file or a directory with multiple files for better organization.

**Single-file approach:**
```
host_vars/
└── hostname.example.com.yml
```

**Multi-file approach (recommended for complex configurations):**
```
host_vars/
└── hostname.example.com/
    ├── network.yml      # Network configuration (bonds, bridges, VLANs)
    ├── hypervisor.yml   # Hypervisor configuration
    └── custom.yml       # Any other host-specific variables
```

Common configuration files:
- **network.yml**: Network configuration (bonds, bridges, VLANs)
- **hypervisor.yml**: KVM/QEMU hypervisor configuration settings
  - Nested virtualization options
  - IP forwarding settings
  - Firewall and bridge netfilter configuration

## Hypervisor Configuration

The hypervisor role can be configured with different combinations:

### Option 1: Disable firewalld completely (traditional approach)
```yaml
hypervisor_disable_firewall: true
hypervisor_disable_bridge_netfilter: false
```

### Option 2: Keep firewalld but disable bridge filtering (recommended)
```yaml
hypervisor_disable_firewall: false
hypervisor_disable_bridge_netfilter: true
```
This allows firewalld to protect the host while VM bridge traffic is not filtered.

### Option 3: Full firewall protection (requires custom firewall rules)
```yaml
hypervisor_disable_firewall: false
hypervisor_disable_bridge_netfilter: false
```
Requires manual firewall configuration for VM networking.
