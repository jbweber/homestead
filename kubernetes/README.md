# Cilium BGP Commands Reference

## Core BGP Status Commands

**Check BGP peer status:**
```bash
cilium bgp peers
# Shows: Local AS, Peer AS, Peer Address, Session status, Uptime, Family, Routes received/advertised
```

**General Cilium status with BGP info:**
```bash
cilium status --verbose
```

## BGP Route Commands

**Show routes advertised to peers:**
```bash
cilium bgp routes advertised ipv4 unicast
```

**Show routes received from peers:**
```bash
# Note: 'received' may not be available in all Cilium versions
# Use 'cilium bgp peers' to see received route counts instead
cilium bgp peers
```

**Show all available routes in BGP table:**
```bash
cilium bgp routes available ipv4 unicast
```

## Using cilium-dbg (Pod Execution)

When running from outside the cluster or if `cilium` command isn't available:

```bash
kubectl exec -it -n kube-system ds/cilium -- cilium-dbg bgp peers
kubectl exec -it -n kube-system ds/cilium -- cilium-dbg bgp routes advertised ipv4 unicast
kubectl exec -it -n kube-system ds/cilium -- cilium-dbg bgp routes available ipv4 unicast
# Note: 'received' command may not be available in all versions
```

## Kubernetes Resource Commands

**Check BGP configurations:**
```bash
kubectl get ciliumbgpclusterconfigs
kubectl get ciliumbgppeerconfigs
kubectl get ciliumbgpadvertisements
kubectl get ciliumbgpnodeconfigs
```

**Detailed view:**
```bash
kubectl describe ciliumbgpnodeconfigs
kubectl describe ciliumbgpclusterconfigs
kubectl describe ciliumbgppeerconfigs
```

## IPv6 Variants

Replace `ipv4` with `ipv6` for IPv6 routes:
```bash
cilium bgp routes advertised ipv6 unicast
cilium bgp routes available ipv6 unicast
# Note: 'received' may not be available - use 'cilium bgp peers' for route counts
```

## Common Troubleshooting Sequence

1. **Check peer connectivity:**
   ```bash
   cilium bgp peers
   ```

2. **Verify route advertisement:**
   ```bash
   cilium bgp routes advertised ipv4 unicast
   ```

3. **Check received routes (via peer status):**
   ```bash
   cilium bgp peers
   # Look at the "Received" column for route counts
   ```

4. **Review configuration status:**
   ```bash
   kubectl describe ciliumbgpnodeconfigs
   ```