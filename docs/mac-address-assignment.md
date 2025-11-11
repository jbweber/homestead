# MAC Address Assignment for Virtual Machines

## Overview

This document describes the deterministic MAC address assignment pattern used for VMs in the homestead infrastructure.

## Pattern

All VMs use locally administered MAC addresses calculated from their IP address:

```
MAC = be:ef:XX:XX:XX:XX
```

Where `XX:XX:XX:XX` are the four octets of the VM's IPv4 address in hexadecimal.

### Examples

| IP Address | MAC Address | Calculation |
|------------|-------------|-------------|
| 10.230.230.101 | be:ef:0a:e6:e6:65 | 0a=10, e6=230, e6=230, 65=101 |
| 10.230.230.102 | be:ef:0a:e6:e6:66 | 0a=10, e6=230, e6=230, 66=102 |
| 192.168.1.100 | be:ef:c0:a8:01:64 | c0=192, a8=168, 01=1, 64=100 |

## Why This Works

### MAC Address Scope

Like IPv4 addresses, **MAC addresses are not globally unique identifiers**. They only need to be unique within their **Layer 2 (L2) broadcast domain**:

- MAC addresses operate at Layer 2 and are only relevant within a single broadcast domain (VLAN, physical network segment)
- Routers do not forward MAC addresses between networks - they are stripped and replaced at each Layer 3 hop
- Each broadcast domain is isolated, so the same MAC address could theoretically exist on different networks without conflict

**This is why IP-based MAC generation works**: Within a given L2 domain, if IP addresses are unique, the calculated MAC addresses will also be unique within that scope. There's no risk of collision as long as IP addresses don't collide within the broadcast domain.

### Locally Administered Address

The `be:ef` prefix creates a **locally administered unicast** MAC address:

- First octet `be` (binary: `1011 1110`):
  - Bit 0 (LSB): **0** = Unicast (not multicast)
  - Bit 1: **1** = Locally administered (not universally administered)

For a MAC address first octet, if the second hex digit is `2`, `6`, `A`, or `E`, it's a valid locally administered address. The `be` octet has `e` as the second digit, making it valid.

### Standards Compliance

This approach follows IEEE 802 standards:
- **Unicast**: The address identifies a single network interface
- **Locally Administered**: Under local network administrator control
- **L2 Scope**: Only needs to be unique within the broadcast domain
- **No Conflicts**: Cannot conflict with vendor-assigned (universally administered) MACs

## Benefits

1. **Deterministic**: Given an IP address, the MAC is always calculable
2. **Collision-Free**: Different IPs always produce different MACs
3. **Standards Compliant**: Properly formed locally administered address
4. **No Central Registry**: No need to track or coordinate MAC assignments
5. **Human Readable**: Easy to verify IP/MAC correspondence

## Implementation

This pattern is used in:
- **dnsmasq role**: Static DHCP host entries
- **libvirt domains**: VM network interface definitions

## Usage in DHCP Configuration

When configuring static DHCP entries for VMs, use the calculated MAC:

```yaml
dnsmasq_dhcp_subnets:
  - name: "lab"
    hosts:
      - ip: "10.230.230.101"
        mac: "be:ef:0a:e6:e6:65"  # Calculated from IP
        hostname: "br230-vm101"
```

## Converting IP to MAC

To calculate a MAC address from an IP:

1. Split IP into octets: `10.230.230.101` → `10`, `230`, `230`, `101`
2. Convert each to hex: `0a`, `e6`, `e6`, `65`
3. Prepend `be:ef:`: `be:ef:0a:e6:e6:65`

Quick reference:
```bash
# Using printf
printf "be:ef:%02x:%02x:%02x:%02x\n" 10 230 230 101
# Output: be:ef:0a:e6:e6:65
```

## Important Notes

- **Only for VMs**: Physical machines use their hardware-assigned MACs
- **IPv4 Only**: This pattern only works for IPv4 addresses
- **Consistent Assignment**: Always use the same IP for a VM to maintain MAC consistency
- **Network Isolation**: The locally administered bit ensures no conflict with real hardware
