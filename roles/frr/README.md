# FRR (Free Range Routing) Ansible Role

This role installs and configures FRR with BGP support.

## Requirements

- RHEL/Fedora/CentOS system with DNF package manager
- FRR package available in repositories

## Role Variables

### Daemon Configuration

```yaml
frr_daemons:
  bgpd: true        # Enable BGP daemon
  ospfd: false      # Enable OSPF daemon
  # ... other daemons default to false
```

### BGP Configuration

```yaml
frr_bgp_enable: true
frr_bgp_asn: 65000                                    # Your BGP AS number
frr_bgp_router_id: "{{ ansible_default_ipv4.address }}"  # BGP router ID
```

### BGP Neighbors

```yaml
frr_bgp_neighbors:
  - ip: 192.168.1.1
    remote_as: 65001
    description: "Peer router 1"
    update_source: eth0                # Optional
    ebgp_multihop: true                # Optional - Boolean flag for multi-hop eBGP
    ttl_security_hops: 2               # Optional - TTL security (mutually exclusive with ebgp_multihop)
    password: "secret"                 # Optional
    route_map_in: "IMPORT-POLICY"      # Optional
    route_map_out: "EXPORT-POLICY"     # Optional
    prefix_list_in: "ALLOW-IN"         # Optional
    prefix_list_out: "ALLOW-OUT"       # Optional
```

### BGP Networks to Announce

```yaml
frr_bgp_networks:
  - prefix: 10.0.0.0/24
  - prefix: 10.0.1.0/24
```

### Additional Configuration

```yaml
frr_additional_config:
  - "ip prefix-list ALLOW-ALL permit 0.0.0.0/0 le 32"
  - "route-map PERMIT-ALL permit 10"
  - " match ip address prefix-list ALLOW-ALL"
```

## Example Playbook

### Basic BGP Setup

```yaml
- hosts: routers
  roles:
    - role: frr
      vars:
        frr_bgp_asn: 65000
        frr_bgp_router_id: 192.168.1.254
        frr_bgp_neighbors:
          - ip: 192.168.1.1
            remote_as: 65001
            description: "ISP Router"
        frr_bgp_networks:
          - prefix: 10.0.0.0/24
```

### Advanced BGP with Route Maps

```yaml
- hosts: routers
  roles:
    - role: frr
      vars:
        frr_bgp_asn: 65000
        frr_bgp_router_id: 192.168.1.254
        frr_bgp_neighbors:
          - ip: 192.168.1.1
            remote_as: 65001
            description: "Upstream Provider"
            route_map_out: "EXPORT-POLICY"
          - ip: 192.168.2.1
            remote_as: 65000
            description: "iBGP Peer"
            update_source: lo0
        frr_bgp_networks:
          - prefix: 10.0.0.0/24
          - prefix: 10.0.1.0/24
        frr_additional_config:
          - "ip prefix-list LOCAL-NETS permit 10.0.0.0/16 le 24"
          - "!"
          - "route-map EXPORT-POLICY permit 10"
          - " match ip address prefix-list LOCAL-NETS"
```

## Configuration Files

The role manages the following files:

- `/etc/frr/daemons` - Controls which FRR daemons are enabled
- `/etc/frr/frr.conf` - Main FRR configuration file

## Handlers

- `Restart frr` - Restarts the FRR service (used when daemon configuration changes)
- `Reload frr` - Reloads the FRR configuration (used when routing configuration changes)

## Notes

- The role validates the FRR configuration using `vtysh -C -f` before applying it
- Configuration changes trigger a reload rather than restart when possible to minimize disruption
- BGP neighbors must be explicitly activated in the IPv4 unicast address family
