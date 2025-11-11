# PXE DHCP Options Reference

## The Three Key Fields

| Field | What It Does | Format |
|-------|--------------|--------|
| **siaddr** (next-server) | Boot server IP address | IP only (e.g., 192.168.1.100) |
| **Option 66** | TFTP server name/IP | IP or DNS name (e.g., tftp.example.com) |
| **Option 67** | Boot filename | Path/filename (e.g., grubx64.efi) |

## Client Priority Order

Most PXE clients check in this order:
1. Option 66 (if present) → use it
2. siaddr (if non-zero) → use it
3. DHCP server IP → use it

**Note:** Not all clients follow this! Some older implementations only check siaddr.

## dnsmasq Configuration

### Basic Syntax

```conf
dhcp-boot=<filename>,[<servername>,][<server-ip>]
```

This sets:
- `filename` → Option 67 (boot file)
- `servername` → Option 66 (optional)
- `server-ip` → siaddr field (optional)

### Recommended: Use siaddr Only (Simplest & Most Compatible)

```conf
# dnsmasq serves TFTP itself (uses own IP automatically)
enable-tftp
tftp-root=/var/lib/tftpboot
dhcp-boot=pxelinux.0

# Or specify external TFTP server
dhcp-boot=pxelinux.0,,192.168.1.100
```

**Why this works best:**
- Maximum compatibility with all PXE implementations
- Works with older BIOS and modern UEFI
- No DNS resolution required during boot
- Simplest configuration

### Architecture-Specific Boot Files

```conf
enable-tftp
tftp-root=/var/lib/tftpboot

# Detect client architecture
dhcp-match=set:bios,option:client-arch,0
dhcp-match=set:efi32,option:client-arch,6
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64,option:client-arch,9
dhcp-match=set:arm64,option:client-arch,11

# Serve appropriate bootloaders
dhcp-boot=tag:bios,pxelinux.0
dhcp-boot=tag:efi32,bootia32.efi
dhcp-boot=tag:efi64,grubx64.efi
dhcp-boot=tag:arm64,grubaa64.efi
```

### Advanced: Using Option 66

Only use if you need DNS names or have specific compatibility requirements:

```conf
# With DNS name (Option 66 + siaddr)
dhcp-boot=grubx64.efi,tftp.example.com,192.168.1.100

# Explicit option setting (rarely needed)
dhcp-option=66,192.168.1.100
dhcp-option=67,grubx64.efi
```

## Common Architecture Codes

| Code | Architecture | Typical Bootloader |
|------|--------------|-------------------|
| 0x0000 | BIOS/Legacy | pxelinux.0 |
| 0x0006 | EFI IA32 | bootia32.efi |
| 0x0007 | EFI BC (bytecode) | grubx64.efi |
| 0x0009 | EFI x86-64 | grubx64.efi |
| 0x000b | EFI ARM 64-bit | grubaa64.efi |

**Note:** EFI BC (0x0007) is often seen on older Intel NICs (like i350). Treat it like x86-64 UEFI.

## Complete Example

```conf
# Enable TFTP server
enable-tftp
tftp-root=/var/lib/tftpboot
tftp-secure

# DHCP range
dhcp-range=192.168.1.50,192.168.1.150,12h

# Architecture detection
dhcp-match=set:bios,option:client-arch,0
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64,option:client-arch,9

# Boot files (using siaddr only - recommended)
dhcp-boot=tag:bios,pxelinux.0
dhcp-boot=tag:efi64,grubx64.efi

# Optional: Enable logging for debugging
log-dhcp
```

## Troubleshooting

```bash
# Run dnsmasq with verbose logging
dnsmasq -d -q --log-dhcp

# Capture DHCP packets to see what client requests
tcpdump -i eth0 -vvv port 67 or port 68

# Test TFTP manually
tftp 192.168.1.100 -c get pxelinux.0
```

## Quick Decision Guide

**Use siaddr only (recommended):**
- ✅ You want maximum compatibility
- ✅ Simple network with fixed TFTP server IP
- ✅ Works with all clients (old and new)

**Add Option 66 only if:**
- You need DNS hostname flexibility
- TFTP server IP changes frequently
- Specific client compatibility issues
- Load-balanced TFTP environment

**Bottom line:** Start with siaddr only. Add Option 66 only if you have a specific reason.