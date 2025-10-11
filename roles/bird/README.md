# BIRD BGP Role for VM Route Announcement

This role configures BIRD (BIRD Internet Routing Daemon) for a very specific use case: announcing VM /32 routes via eBGP.

## Use Case

This role is designed for hypervisors that:
- Create VMs with dedicated tap interfaces named `vm{ip_in_hex}` (e.g., `vm0a371616` for 10.55.22.22)
- Have /32 routes for each VM pointing to their respective tap interface
- Need to announce these VM routes via BGP to an upstream router
- Use 169.254.0.1 as a link-local gateway on each VM interface (not announced)

## Requirements

- RHEL/Fedora/CentOS system with DNF package manager
- BIRD package available in repositories
- BGP peer configured and reachable

## Role Variables

### Required Variables

```yaml
bird_bgp_local_asn: 65009                    # Your local AS number
bird_bgp_neighbor_ip: 192.168.254.1          # BGP peer IP address
bird_bgp_neighbor_asn: 65001                 # BGP peer AS number
```

### Optional Variables

```yaml
bird_bgp_router_id: "{{ ansible_default_ipv4.address }}"  # BGP router ID
bird_bgp_multihop: true                       # Enable eBGP multihop
bird_vm_interface_pattern: "vm????????"      # Pattern for VM interfaces (vm + 8 hex chars)
bird_linklocal_gateway: "169.254.0.1/32"     # Link-local gateway to exclude
bird_debug_protocols: false                   # Enable verbose protocol debugging in logs
```

## Example Configuration

```yaml
# In host_vars/hypervisor.yml
bird_bgp_local_asn: 65009
bird_bgp_neighbor_ip: 192.168.254.1
bird_bgp_neighbor_asn: 65001
bird_bgp_multihop: true
```

## Example Playbook

```yaml
- hosts: hypervisor
  roles:
    - role: bird
      become: true
      when: bird_bgp_local_asn is defined
```

## How It Works

1. **Kernel Protocol**: Imports all routes from kernel with `learn` enabled (to learn "alien routes" not added by BIRD)
2. **Direct Protocol**: Learns about directly connected interfaces (watches vm* interfaces)
3. **BGP Export Filter**: Filters at export time to only announce routes that:
   - Are /32 host routes
   - Are on interfaces matching `vm????????` pattern (vm + 8 hex digits representing IP in hex)
   - Are NOT the link-local gateway (169.254.0.1/32)
4. **BGP Import**: Denies all inbound routes from the peer

The key design principle: Import everything, filter at BGP export. This is more reliable than filtering at kernel import.

## BIRD Commands

```bash
# Check BIRD status
birdc show status

# Show BGP protocol status
birdc show protocols

# Show all routes BIRD knows about
birdc show route

# Show routes imported from kernel
birdc show route protocol kernel1

# Show what's being exported to BGP peer
birdc show route export upstream

# Show BGP protocol details
birdc show protocol all upstream

# Reload configuration
birdc configure

# Enable/disable debug mode at runtime
birdc debug protocols all
birdc debug protocols off
```

## Configuration Files

- `/etc/bird.conf` - Main BIRD configuration file (BIRD 3.x uses root of /etc)

## Handlers

- `Reload bird` - Reloads BIRD configuration without restarting
- `Restart bird` - Restarts the BIRD service

## Notes

- **BIRD Version**: Tested with BIRD 3.x (config file at `/etc/bird.conf`)
- **Pattern Matching**: The `~` operator supports shell-style wildcards (`vm????????` matches vm + exactly 8 chars)
- **Interface Naming**: `vm` + 8 hex chars = 10 total chars (well under Linux's 15 char limit)
  - Example: `10.55.22.22` = `0x0a371616` = `vm0a371616`
- **Learn Option**: Required to import routes added by libvirt hooks or manually (not created by BIRD)
- **Validation**: Configuration is validated using `bird -p` before applying
- **Graceful Reload**: Changes trigger a reload rather than restart to minimize disruption
