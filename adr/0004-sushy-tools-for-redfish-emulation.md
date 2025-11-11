---
status: accepted
date: 2025-11-10
---

# Sushy-tools for Redfish Emulation

## Context and Problem Statement

Metal3 requires Redfish or IPMI BMC (Baseboard Management Controller) access to manage bare metal hosts (power control, boot device selection, hardware inspection). Development and testing environments using virtualization (libvirt/KVM VMs) lack physical BMC hardware. How should BMC functionality be emulated for virtual machines to enable Metal3 provisioning workflows?

## Decision Drivers

* Development/testing enablement - Support Metal3 workflows without physical hardware
* API compatibility - Provide standard Redfish API that Metal3 expects
* Operational simplicity - Minimal setup and maintenance overhead
* Virtualization integration - Native support for libvirt/KVM environments
* Production applicability - Pattern applicable to physical hardware transition
* Resource efficiency - Minimal overhead for emulation layer

## Considered Options

* **Option 1**: Sushy-tools Redfish emulator
* **Option 2**: Virtual BMC (vbmc) - IPMI emulation
* **Option 3**: Custom Redfish API implementation
* **Option 4**: Physical hardware with real BMCs
* **Option 5**: Skip emulation, use cloud provider VMs

## Decision Outcome

Chosen option: **"Sushy-tools Redfish emulator"**, because it provides standard Redfish API emulation for libvirt VMs, follows modern BMC standards (Redfish over legacy IPMI), and is actively maintained by the OpenStack community.

The implementation uses:
- Sushy-tools running as a service (container or systemd unit)
- Libvirt backend for VM power/boot control
- Redfish API endpoints accessible to Metal3 baremetal-operator
- Per-VM Redfish URLs configured in BareMetalHost resources

### Consequences

* Good, because enables Metal3 development/testing on virtualized infrastructure
* Good, because uses modern Redfish standard (not legacy IPMI)
* Good, because actively maintained by OpenStack Ironic community
* Good, because native libvirt integration (direct virsh API usage)
* Good, because minimal resource overhead (lightweight Python service)
* Good, because skills transfer to physical hardware (same Redfish API)
* Good, because supports testing complete Metal3 workflow
* Bad, because emulation doesn't match physical BMC behavior perfectly
* Bad, because requires libvirt access for sushy-tools service
* Bad, because another service to deploy and maintain
* Neutral, because development/testing only (physical hardware uses real BMCs)
* Neutral, because Redfish endpoint network accessibility must be planned

### Confirmation

This decision is validated through operational experience:
1. Sushy-tools successfully emulating Redfish for libvirt VMs
2. Metal3 baremetal-operator successfully managing VM power states
3. Hardware inspection working via emulated Redfish API
4. Boot device selection (disk vs network boot) functioning correctly
5. VM provisioning workflow identical to physical hardware workflow
6. Transition path to physical hardware straightforward (change BMC URL only)

## Pros and Cons of the Options

### Option 1: Sushy-tools Redfish emulator

* Good, because provides standard Redfish API
* Good, because actively maintained (OpenStack Ironic project)
* Good, because native libvirt integration
* Good, because lightweight and resource-efficient
* Good, because modern API standard (Redfish)
* Good, because supports development workflow testing
* Bad, because emulation not perfect match for physical BMCs
* Bad, because requires libvirt access (security consideration)
* Neutral, because development/testing focused

### Option 2: Virtual BMC (vbmc) - IPMI emulation

* Good, because provides BMC emulation for VMs
* Good, because IPMI widely understood
* Bad, because IPMI is legacy standard (being replaced by Redfish)
* Bad, because less actively maintained than sushy-tools
* Bad, because encourages IPMI patterns rather than modern Redfish
* Bad, because learning investment in deprecated technology

### Option 3: Custom Redfish API implementation

* Good, because full control over implementation
* Good, because can optimize for specific use case
* Bad, because significant development and maintenance burden
* Bad, because Redfish specification is complex
* Bad, because reinventing existing solution
* Bad, because compatibility issues likely with Metal3/Ironic expectations

### Option 4: Physical hardware with real BMCs

* Good, because production-representative environment
* Good, because no emulation layer
* Good, because tests real hardware interactions
* Bad, because requires significant hardware investment
* Bad, because higher operational costs (power, space, cooling)
* Bad, because slower iteration cycles (physical provisioning)
* Bad, because not accessible for all development scenarios
* Neutral, because still valuable for production validation

### Option 5: Skip emulation, use cloud provider VMs

* Good, because no local infrastructure needed
* Good, because scalable resources
* Bad, because Metal3 designed for bare metal, not cloud VMs
* Bad, because doesn't test actual Metal3 workflow
* Bad, because no BMC layer to test
* Bad, because different from production environment
* Bad, because ongoing cloud costs

## More Information

This decision was made based on requirements for:
- Development and testing of Metal3 provisioning workflows
- Resource-constrained environments where physical hardware unavailable
- Learning and validation before physical hardware deployment
- Cost-effective infrastructure for iteration and testing

Sushy-tools deployment considerations:
- **Location**: Typically runs on hypervisor host or management network
- **Access**: Requires libvirt socket access (local or remote via SSH/TLS)
- **Network**: Redfish endpoints must be accessible from Metal3 management cluster
- **Security**: Libvirt access control important (full VM control)
- **Authentication**: Supports basic auth for Redfish endpoints

BareMetalHost configuration pattern:
```yaml
spec:
  bmc:
    address: redfish-virtualmedia://sushy-host:8000/redfish/v1/Systems/vm-uuid
    credentialsName: vm-bmc-secret
```

Transition to physical hardware:
- Change BMC address from sushy-tools URL to physical BMC URL
- Update credentials to physical BMC credentials
- Metal3 workflow remains identical (same API)
- Skills and patterns transfer directly

Physical hardware still requires real BMCs:
- This decision applies to development/testing environments
- Production physical hardware uses native BMC (iDRAC, iLO, BMC)
- Sushy-tools pattern validates workflow before hardware investment

Related decisions:
- ADR-0000: Bare Metal Provisioning Approach (Metal3 requires BMC access)
- ADR-0002: Metal3 Management Cluster Architecture (where Metal3 controllers run)
- ADR-0003: Netboot Server for PXE Provisioning (triggered via BMC boot device control)
