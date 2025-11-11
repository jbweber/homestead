# CAPI/Metal3 TODO and Future Improvements

This document tracks learnings, design decisions, and areas for future investigation and improvement in our Cluster API and Metal3 deployments.

**Architecture Decision Records**: See [../adr/README.md](../adr/README.md) for comprehensive documentation of all architectural decisions made for this stack.

**Cluster Provisioning Template**: See [CLUSTER_TEMPLATE.md](CLUSTER_TEMPLATE.md) for complete guide on creating new clusters from Metal3 foundation, including BareMetalHost registration, inspection, network configuration, and deployment workflows.

## Current Status

### What Works
- ✅ Metal3 management cluster (metal3.cofront.xyz)
- ✅ BareMetalHost registration and inspection
- ✅ Single-node cluster deployment (super cluster)
- ✅ **BMH networkData approach** (RECOMMENDED - pre-configure network on BMH, CAPI preserves it)
- ✅ nmcli-based network configuration (DEPRECATED - use BMH networkData instead)
- ✅ Cilium CNI with kube-proxy replacement (ClusterResourceSet deployment)
- ✅ Cilium BGP control plane for pod CIDR advertisement
- ✅ DNS readiness wait pattern
- ✅ kube-vip for HA control plane VIP in ARP mode
- ✅ Multi-node HA cluster pattern (capi-1: 3 control planes + 1 worker)
- ✅ Worker node role labeling (manual label application to clean up `kubectl get nodes` output)
- ✅ Adding workers to existing clusters
- ✅ Complex network configs (bonds, VLANs) via OpenStack network_data.json format
- ✅ End-to-end cluster reprovisioning (validated 2025-11-10)

### Deployment Pattern Established
- **Networking**: Use BMH `spec.networkData` with OpenStack network_data.json format (works for simple and complex configs)
- **Architecture**: Templates + MachineDeployments (KubeadmControlPlane for control planes, MachineDeployment for workers)
- **Network config storage**: Per-node secrets with OpenStack format, referenced in BMH before CAPI claims
- **CNI**: Cilium deployed via ClusterResourceSet with rendered manifests
  - kube-proxy replacement enabled (kubeadm configured to skip kube-proxy installation)
  - Native routing (no tunnels) for bare metal performance
  - BGP control plane for pod CIDR advertisement
  - **CRITICAL**: Must set k8sServiceHost/Port to control plane VIP to avoid bootstrap chicken-and-egg problem
- **BGP Routing**: Cilium BGP v2 API (CiliumBGPClusterConfig, CiliumBGPPeerConfig, CiliumBGPAdvertisement)
  - Each node advertises its PodCIDR to upstream router
  - FRR peer-groups simplify router configuration
- **kube-vip**: Static pod in preKubeadmCommands on all control plane nodes (leader election handles VIP failover)

## TODO: Investigate and Improve

### High Priority

#### 0. BMH networkData Approach - ✅ VALIDATED AND WORKING
**Status**: Successfully deployed and validated (2025-11-10)

**What was validated**:
- ✅ Simple static IP configs (3 control planes + 1 worker with single interface)
- ✅ Complex bond+VLAN configs (super node with bond0.2000)
- ✅ CAPI preserves BMH `spec.networkData` when claiming hosts
- ✅ No nmcli commands needed in preKubeadmCommands
- ✅ OpenStack network_data.json format works perfectly
- ✅ Adding workers to existing cluster works seamlessly
- ✅ All nodes provisioned and running with correct network configs

**Proven benefits**:
- Simpler CAPI manifests (no network logic in preKubeadmCommands)
- Separation of concerns (network config managed at BMH level)
- Avoids Metal3DataTemplate networkData bugs
- Easy to update network configs independently
- Same format works for simple and complex configs (single interface, bonds, VLANs)
- Easier to reason about and debug

**Implementation files**:
- Example manifest: `~/projects/environment-files/capi-1/capi-1-bmh-network-experiment.yaml`
- Network configs: `~/projects/homestead/capi/network-configs/`
- Documentation: `~/projects/homestead/capi/net-config-option.md`

**This is now the RECOMMENDED approach for all future deployments.**

#### 1. Dynamic Network Configuration
**Current**: Hard-coded IP addresses and interface names in nmcli commands
**Goal**: Use Metal3 metadata or IPPools to dynamically assign IPs per node
**Investigation needed**:
- Can cloud-init metadata provide node-specific IPs reliably?
- Can Metal3DataTemplate variables reference IPPool allocations?
- Best practice for mapping BareMetalHost → specific IP address
- Consider using `{{ ds.meta_data.local-ipv4 }}` or similar templating
**Benefit**: Eliminate manual IP configuration, enable true scaling

#### 2. Interface Name Detection
**Current**: Hard-coded `ens3` interface name
**Goal**: Dynamically detect primary network interface
**Investigation needed**:
- Query interface from BareMetalHost hardware details
- Use cloud-init network metadata
- Fallback detection script (find interface with link and no IP)
**Benefit**: Work across different VM/hardware configurations

#### 3. Metal3DataTemplate networkData Revisited
**Current**: Avoiding due to bugs with bonds/VLANs, using nmcli instead
**Goal**: Understand when Metal3DataTemplate networkData is safe to use
**Investigation needed**:
- Test simple static IP configs (no bonds/VLANs) with networkData
- Identify specific bugs and Metal3 versions affected
- Monitor upstream Metal3 fixes
- Document when to use networkData vs. nmcli
**Benefit**: Use native Metal3 features when appropriate, reduce preKubeadmCommands complexity

#### 4. IPPool Integration
**Current**: Not using Metal3 IPPools
**Goal**: Leverage IPPools for automated IP assignment
**Investigation needed**:
- Create per-node IPPools with single IP range
- Reference IPPools from Metal3DataTemplate
- Verify IP allocation matches BareMetalHost labels
- Integration with nmcli-based network config
**Benefit**: Automated IP management, better integration with Metal3 IPAM

### Medium Priority

#### 5. kube-vip Configuration Options
**Current**: ARP mode for simple L2 VIP
**Goal**: Evaluate BGP mode for production
**Investigation needed**:
- BGP mode configuration and requirements
- Integration with network infrastructure
- Comparison: ARP vs. BGP for HA control plane
- LoadBalancer service support (svc_enable: true)
**Benefit**: More robust networking, potential for service load balancing

#### 6. Image Building Pipeline
**Current**: Using pre-built fedora-43-ext4-k8s.raw image
**Goal**: Document and automate image building
**Investigation needed**:
- Image build process (what tools/scripts?)
- Kubernetes version updates
- OS package updates and security patches
- Storage on netboot.cofront.xyz
- Image versioning strategy
**Benefit**: Reproducible image builds, security updates, version control

#### 7. Multi-Cluster Patterns
**Current**: Individual cluster manifests per deployment
**Goal**: Establish patterns for managing multiple clusters
**Investigation needed**:
- Naming conventions for clusters
- Shared vs. per-cluster Metal3DataTemplates
- Network isolation between clusters
- Resource allocation and BareMetalHost labeling
**Benefit**: Scale to multiple clusters efficiently

#### 8. Cluster Upgrades
**Current**: No upgrade strategy defined
**Goal**: Safe Kubernetes version upgrades
**Investigation needed**:
- KubeadmControlPlane rolling upgrade behavior
- MachineDeployment rolling upgrade strategy
- Image updates vs. in-place upgrades
- Backup and recovery procedures
**Benefit**: Keep clusters up-to-date with minimal downtime

### Low Priority

#### 9. Alternative CNI Evaluation - ✅ COMPLETED (Cilium Adopted)
**Status**: Cilium deployed and validated (2025-11-10)
**What was implemented**:
- ✅ Cilium CNI with kube-proxy replacement
- ✅ Native routing (no tunnels) for bare metal performance
- ✅ BGP control plane for pod CIDR advertisement to upstream router
- ✅ ClusterResourceSet deployment pattern with rendered manifests
- ✅ k8sServiceHost/Port bootstrap fix documented
- ✅ FRR peer-group configuration for simplified router config
**Benefits achieved**:
- eBPF-based networking and observability
- BGP routing integration with infrastructure
- kube-proxy replacement reduces overhead
- Production-grade CNI with advanced features
**Next**: Consider Cilium network policies, Hubble observability, service mesh features

#### 10. Monitoring and Observability
**Current**: Basic kubectl commands for status
**Goal**: Comprehensive monitoring of clusters
**Investigation needed**:
- Prometheus/Grafana deployment patterns
- CAPI metrics and dashboards
- Metal3/Ironic monitoring
- Alerting for cluster issues
**Benefit**: Proactive issue detection, better debugging

#### 11. Cluster API Provider Performance
**Current**: Using CAPM3 (Metal3 provider)
**Goal**: Optimize provisioning speed
**Investigation needed**:
- Parallel vs. sequential node provisioning
- Image caching strategies
- Ironic configuration tuning
- Network boot optimization
**Benefit**: Faster cluster deployments

#### 12. GitOps Integration
**Current**: Manual kubectl apply
**Goal**: GitOps workflow with Flux or ArgoCD
**Investigation needed**:
- Flux vs. ArgoCD for CAPI
- Secrets management
- Multi-cluster management with GitOps
- Drift detection and reconciliation
**Benefit**: Declarative infrastructure, audit trail

## Design Decisions Log

### clusterctl generate vs. Hand-Crafted Manifests?
**Decision**: Create manifests directly instead of using `clusterctl generate cluster`
**Reason**:
- `clusterctl generate` is a scaffolding tool that does simple variable substitution
- It generates basic, generic manifests that need heavy customization anyway
- Our requirements (kube-vip, nmcli networking, DNS waits, CNI, user setup) require extensive customization
- Hand-crafted manifests based on working reference (super cluster) are more efficient and explicit
**Workflow**: Use `clusterctl generate` once to learn the structure, then maintain complete manifests directly
**Review**: This approach works well - manifests are ready to apply without generation step

### How to Determine Interface Names?
**Decision**: Query BareMetalHost inspection data for actual interface names
**Method**: `kubectl get bmh <name> -o jsonpath='{.status.hardware.nics}' | jq -r '.[].name'`
**Result**: Discovered `ens2` (not `ens3`) for libvirt virtio devices
**Lesson**: Always verify interface names from BMH hardware data before deploying
**Review**: Critical step - wrong interface name would cause networking to fail

### Why nmcli Instead of Metal3DataTemplate networkData?
**Decision**: Use nmcli in preKubeadmCommands for all network configuration
**Reason**: Metal3DataTemplate networkData has rendering bugs with complex configs (bonds/VLANs) seen in super cluster
**Trade-off**: More verbose, not using native Metal3 features, but proven to work reliably
**Review**: Revisit when Metal3 networkData bugs are resolved upstream

### Why Hard-coded Values Initially?
**Decision**: Hard-code interface names and IPs in initial implementation
**Reason**: Establish working pattern quickly, hand off to engineering teams for refinement
**Trade-off**: Not DRY, manual updates needed, but clear and explicit
**Review**: Address with dynamic configuration (TODO items 1, 2, 4)

### Why KubeadmControlPlane + MachineDeployment?
**Decision**: Use Templates + MachineDeployments (Option A from capi-config-options)
**Reason**: Simpler for homogeneous hardware, easier scaling, less YAML
**Trade-off**: Less per-node control, assumes nodes are similar
**Review**: Works well for capi-1 (identical VMs), may need Individual Machines for mixed hardware

### Why Cilium CNI?
**Decision**: Deploy Cilium via ClusterResourceSet with rendered manifests
**Reason**: Production-grade CNI with eBPF, BGP support, kube-proxy replacement
**Key Features**:
- Native routing (no tunnels) for bare metal performance
- BGP control plane for pod CIDR advertisement
- kube-proxy replacement reduces overhead
- Advanced observability with Hubble
- Network policy support
**Critical Fix**: Must set k8sServiceHost/Port to control plane VIP to avoid bootstrap chicken-and-egg problem
**Review**: Proven working in capi-1 cluster, now recommended for all clusters

### Why kube-vip ARP Mode?
**Decision**: kube-vip in ARP mode for control plane VIP
**Reason**: Simple L2 solution, no BGP infrastructure required
**Trade-off**: Limited to single L2 network, not as robust as BGP
**Review**: Consider BGP mode for production clusters with appropriate network infrastructure

## References and Learning Resources

- [Metal3 Documentation](https://metal3.io/)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)
- [CAPI Configuration Options](capi-config-options.md) - Our research doc
- [kube-vip Documentation](https://kube-vip.io/)
- [Flannel Documentation](https://github.com/flannel-io/flannel)
- [Super Cluster Manifest](../../environment-files/super-single-node/super-manifest.yaml) - Working reference implementation

## Lessons Learned During capi-1 Deployment

### Pre-Deployment Checklist
1. ✅ **Verify interface names from BMH inspection data** - Don't assume `ens3`, check actual hardware
   - Command: `kubectl get bmh <name> -o jsonpath='{.status.hardware.nics}' | jq -r '.[].name'`
   - capi-1 VMs use `ens2` (not `ens3` as initially assumed)
2. ✅ **Use dry-run before actual deployment** - Validates manifest without making changes
3. ✅ **All BareMetalHosts must be in "available" state** - Check with labels filter
4. ✅ **DNS records should be pre-configured** - VIP DNS record resolves before deployment
5. ✅ **Image and checksum URLs must be accessible** - From both management cluster and target nodes

### Manifest Creation Workflow
1. **Don't regenerate with clusterctl for production** - Creates basic scaffolding only
2. **Base on working reference** - Use proven patterns (super cluster) as template
3. **Hard-code initially, document TODOs** - Get it working first, optimize later
4. **Version control everything** - Manifests, scripts, documentation
5. **Test interface names before deployment** - Query BMH inspection data

### What Worked Well
- ✅ nmcli-based networking pattern (consistent, explicit)
- ✅ kube-vip static pod in preKubeadmCommands (VIP ready before kubeadm)
- ✅ Dynamic Kubernetes 1.29+ workaround (version-aware, node-aware)
- ✅ DNS readiness wait (prevents kubeadm failures)
- ✅ Flannel in postKubeadmCommands (simple, proven)
- ✅ Templates + MachineDeployments architecture (simpler than individual Machines)
- ✅ Comprehensive README with monitoring commands
- ✅ crictl debugging pattern (documented for future troubleshooting)
- ✅ Research-first approach for kube-vip config (found correct env vars)

### What to Watch
- Image provisioning time (5-15 minutes typical)
- DNS resolution inside nodes (60-second timeout in preKubeadmCommands)
- kube-vip claiming VIP (check with `curl -k https://<VIP>:6443/version`)
- Control plane sequential bootstrap (CAPI creates one at a time by default)
- Flannel DaemonSet deployment to all nodes

### Debugging Kubernetes Before Cluster is Ready

When the cluster is bootstrapping and kubectl doesn't work yet, SSH to the node and use `crictl`:

```bash
# SSH to the first control plane node
ssh jweber@<node-ip>

# List all containers (including stopped/crashed)
sudo crictl ps -a

# Get logs from a specific container
sudo crictl logs <container-id>

# Get logs from most recent kube-vip container (example)
sudo crictl logs $(sudo crictl ps -a | grep kube-vip | head -1 | awk '{print $1}')

# Watch kubelet logs
sudo journalctl -u kubelet -f

# Check static pod manifests
sudo ls -la /etc/kubernetes/manifests/

# Edit static pod manifests (will auto-restart)
sudo vi /etc/kubernetes/manifests/kube-vip.yaml
```

**Why this is needed**: During initial cluster bootstrap, the API server may be starting or kube-vip may be crashing before the cluster is accessible via kubectl. `crictl` is the low-level container runtime CLI that works even when Kubernetes is not yet ready.

### kube-vip Configuration Issues Encountered

**Issue 1: vip_address with CIDR notation causes DNS lookup**
- **Error**: `lookup 10.250.250.29/32: no such host`
- **Root cause**: Using deprecated `vip_address` variable with CIDR notation
- **Fix**: Use `address` variable (without CIDR) + separate `vip_subnet` variable
- **Correct configuration**:
  ```yaml
  - name: address
    value: "10.250.250.29"
  - name: vip_subnet
    value: "32"
  ```
- **Reference**: kube-vip v1.0.1+ uses `address` (not `vip_address` which is deprecated)

**Issue 2: kube-vip RBAC permissions for leader election (Kubernetes 1.29+)**
- **Error**: `error retrieving resource lock kube-system/plndr-cp-lock: leases.coordination.k8s.io "plndr-cp-lock" is forbidden`
- **Root cause**: Starting with Kubernetes 1.29+, `admin.conf` initially lacks cluster-admin permissions during bootstrap. kube-vip needs elevated permissions to acquire resource locks.
- **Fix**: Automatically modify kube-vip manifest on kubeadm init to use `super-admin.conf`
- **Implementation** (based on CAPI vsphere provider pattern):
  ```bash
  # In preKubeadmCommands, add a script that:
  # 1. Checks if Kubernetes version is 1.29+
  # 2. Checks if this is kubeadm init (not join)
  # 3. If both true, modifies kube-vip manifest to use super-admin.conf

  # The kube-vip manifest starts with admin.conf
  # On kubeadm init for k8s 1.29+, script changes it to super-admin.conf
  # On kubeadm join, manifest stays as admin.conf (which works for join nodes)
  ```
- **Reference**:
  - https://github.com/kube-vip/kube-vip/issues/684
  - https://github.com/kubernetes-sigs/cluster-api-provider-vsphere/blob/v1.13.1/templates/cluster-template.yaml#L178-L224
- **Why this approach**:
  - Version-aware (only applies workaround when needed)
  - Works correctly on both init and join
  - Follows upstream CAPI provider patterns
  - Static pods can't use ServiceAccount tokens, must use kubeconfig file

## Notes for Engineering Teams

When taking over this infrastructure:

1. **Test in dev first**: capi-1 cluster is a test bed, validate changes there before production
2. **Document patterns**: Update this TODO and create DESIGN.md as patterns solidify
3. **Address TODOs incrementally**: High priority items enable better automation
4. **Monitor upstream**: Watch Metal3/CAPI releases for bug fixes (especially networkData)
5. **Version control everything**: All manifests, images, configurations in Git
6. **Consistent patterns**: When changing approaches, update all clusters for consistency

## Future Design Document

Once patterns stabilize and TODOs are addressed, consolidate learnings into:
- **`DESIGN.md`**: Comprehensive design specification for CAPI/Metal3 infrastructure
- Include: Architecture, network design, deployment workflows, upgrade procedures
- Reference implementation: Templates and examples for common scenarios
