# Ansible Role: dnsmasq

Configures dnsmasq for DHCP, TFTP, and PXE boot services on Fedora systems.

## Description

This role installs and configures dnsmasq specifically for PXE boot environments with:
- DHCP server with static host assignments
- TFTP server (always enabled at `/var/lib/tftpboot`)
- PXE boot with iPXE support (always enabled)
- Automatic installation of iPXE boot images
- Configurable network interface binding

The role uses a minimal base configuration in `/etc/dnsmasq.conf` and places all service-specific configuration in drop-in files under `/etc/dnsmasq.d/`.

**Note**: This role is opinionated and designed for PXE boot/build environments. TFTP and PXE are always enabled.

## Requirements

- Fedora-based system
- Root or sudo access

## Role Variables

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `dnsmasq_interfaces` | `[]` | List of network interfaces to bind to (empty = all interfaces) |

**Note**: DNS is always disabled (port=0) as this role is designed for DHCP/TFTP/PXE only. Interface binding always uses `bind-dynamic` mode for flexibility.

#### Interface Binding Behavior

- **Empty list** (`[]`): `bind-dynamic` applies to all interfaces - dnsmasq listens on all current and future interfaces
- **Specified interfaces**: `bind-dynamic` applies only to listed interfaces - dnsmasq listens only on those interfaces and automatically adapts to IP changes on them
- **Wildcard support**: Trailing wildcards are supported (e.g., `ens*`, `eth*`, `br*`)

Examples:
```yaml
# Single interface
dnsmasq_interfaces:
  - ens2

# Multiple interfaces
dnsmasq_interfaces:
  - ens2
  - eth0

# Wildcard pattern
dnsmasq_interfaces:
  - "ens*"

# All interfaces (default)
dnsmasq_interfaces: []
```

### DHCP Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `dnsmasq_dhcp_subnets` | `[]` | List of subnet configurations (see below) |
| `dnsmasq_dhcp_ignore_unknown` | `true` | Ignore DHCP requests from unknown hosts |

**Note**: DHCP logging is always enabled (`log-dhcp`) for debugging and troubleshooting.

#### Subnet Configuration

Each subnet in `dnsmasq_dhcp_subnets` supports the following fields:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Tag name for this subnet (used for isolation) |
| `subnet` | Yes | Subnet address (e.g., `192.0.2.0`) |
| `netmask` | Yes | Subnet mask (e.g., `255.255.255.0`) |
| `mode` | Yes | `static` (only serve known hosts) or `dynamic` (allocate from range) |
| `range` | If dynamic | DHCP range (e.g., `192.0.2.50,192.0.2.150`) |
| `gateway` | Yes | Gateway address for this subnet |
| `dns_servers` | Yes | List of DNS server addresses |
| `domain` | Yes | Domain name for this subnet |
| `lease_time` | No | Lease time (e.g., `24h`, `12h`) - uses dnsmasq default if omitted |
| `extra_options` | No | List of additional DHCP options (see below) |
| `hosts` | No | List of static host assignments for this subnet (see below) |

### PXE Boot Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `dnsmasq_pxe_server_ip` | `{{ ansible_default_ipv4.address }}` | TFTP server IP |

**Notes**:
- TFTP is always enabled at `/var/lib/tftpboot` with secure mode (files must be owned by `dnsmasq` user)
- iPXE boot images are automatically installed from the `ipxe-bootimgs-x86` package
- Boot files are hardcoded: `ipxe-snponly-x86_64.efi` (EFI loader) and `boot.ipxe` (boot script)
- A default `boot.ipxe` is created that boots from local disk (only if the file doesn't already exist)
- PXE boot always matches EFI architectures 7 (EFI byte code) and 9 (x86_64)
- SELinux context restoration is automatic when SELinux is enabled
- To customize PXE boot behavior, create a custom `boot.ipxe` in `/var/lib/tftpboot/` (role will not overwrite it)

## Multi-Subnet DHCP Configuration

This role supports multiple isolated DHCP subnets using dnsmasq tags. Each subnet can have its own:
- DHCP range (static or dynamic)
- Gateway, DNS servers, and domain
- Custom DHCP options
- Static host assignments

### Single Subnet Example

```yaml
dnsmasq_dhcp_subnets:
  - name: "default"
    subnet: "192.0.2.0"
    netmask: "255.255.255.0"
    mode: "static"
    gateway: "192.0.2.1"
    dns_servers:
      - "192.0.2.1"
    domain: "example.org"
    hosts:
      - ip: "192.0.2.10"
        mac: "02:00:00:11:22:33"
        hostname: "server1"
      - ip: "192.0.2.11"
        mac: "02:00:00:aa:bb:cc"
        hostname: "server2"
```

### Multi-Subnet Example

```yaml
dnsmasq_dhcp_subnets:
  - name: "management"
    subnet: "192.0.2.0"
    netmask: "255.255.255.0"
    mode: "static"
    gateway: "192.0.2.1"
    dns_servers:
      - "192.0.2.1"
      - "1.1.1.1"
    domain: "mgmt.example.org"
    lease_time: "24h"
    extra_options:
      - number: 42
        value: "192.0.2.1"  # NTP server
    hosts:
      - ip: "192.0.2.10"
        mac: "02:00:00:11:22:33"
        hostname: "server1"

  - name: "cluster"
    subnet: "198.51.100.0"
    netmask: "255.255.255.0"
    mode: "dynamic"
    range: "198.51.100.100,198.51.100.200"
    gateway: "198.51.100.1"
    dns_servers:
      - "198.51.100.1"
    domain: "cluster.example.org"
    lease_time: "12h"
    extra_options:
      - number: 26
        value: "1500"  # MTU
    hosts:
      - ip: "198.51.100.10"
        mac: "02:00:00:aa:bb:01"
        hostname: "node1"
```

### How Subnet Isolation Works

- Each subnet is assigned a tag (the `name` field)
- `dhcp-range` with `set:tagname` automatically tags clients based on which subnet they're in
- `dhcp-host` entries use `set:tagname` to associate static assignments with the correct subnet
- `dhcp-option` directives use `tag:tagname` to ensure options only apply to the appropriate subnet
- This ensures complete isolation: clients in one subnet won't receive DHCP options from another

## Dependencies

None.

## Example Playbook

```yaml
- hosts: pxe-servers
  become: true
  gather_facts: true
  roles:
    - role: dnsmasq
      vars:
        # Network configuration
        dnsmasq_interfaces:
          - ens2

        # DHCP configuration
        dnsmasq_dhcp_subnets:
          - name: "default"
            subnet: "192.0.2.0"
            netmask: "255.255.255.0"
            mode: "static"
            gateway: "192.0.2.1"
            dns_servers:
              - "192.0.2.1"
            domain: "example.org"
            hosts:
              - ip: "192.0.2.10"
                mac: "02:00:00:11:22:33"
                hostname: "builder"

        dnsmasq_dhcp_ignore_unknown: true

        # PXE boot configuration
        dnsmasq_pxe_server_ip: "192.0.2.1"
```

## TFTP Security

When `dnsmasq_tftp_secure` is enabled (default), dnsmasq will only serve files owned by the `dnsmasq` user. Ensure your TFTP files have the correct ownership:

```bash
sudo chown -R dnsmasq:dnsmasq /var/lib/tftpboot
```

## SELinux

The role automatically restores SELinux contexts on the TFTP directory when SELinux is enabled. Disable this with:

```yaml
dnsmasq_restore_tftp_context: false
```

## License

MIT

## Author

Jeff Weber (jweber)
