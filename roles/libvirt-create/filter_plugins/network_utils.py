#!/usr/bin/env python3
"""
Custom Ansible filters for network interface processing.
"""


def process_network_interfaces(interfaces):
    """
    Process network interfaces by calculating MAC addresses and interface names
    from IP addresses.

    Args:
        interfaces: List of interface dictionaries with 'ip' key

    Returns:
        List of interface dictionaries with added 'mac', 'ifname', and 'gateway_onlink' keys
    """
    processed = []

    for iface in interfaces:
        # Copy the original interface data
        new_iface = dict(iface)

        # Extract IP without CIDR
        ip_with_cidr = iface['ip']
        ip_only = ip_with_cidr.split('/')[0]
        ip_parts = [int(octet) for octet in ip_only.split('.')]

        # Calculate MAC address: be:ef:xx:xx:xx:xx
        new_iface['mac'] = 'be:ef:{:02x}:{:02x}:{:02x}:{:02x}'.format(*ip_parts)

        # Calculate interface name: vmXXXXXXXX
        new_iface['ifname'] = 'vm{:02x}{:02x}{:02x}{:02x}'.format(*ip_parts)

        # Determine if gateway is on-link (for /32 or /31 networks)
        new_iface['gateway_onlink'] = ip_with_cidr.endswith('/32') or ip_with_cidr.endswith('/31')

        processed.append(new_iface)

    return processed


class FilterModule(object):
    """Ansible filter plugin class."""

    def filters(self):
        return {
            'process_network_interfaces': process_network_interfaces,
        }
