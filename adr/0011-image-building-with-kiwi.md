---
status: accepted
date: 2025-11-10
---

# Image Building with KIWI

## Context and Problem Statement

Metal3 bare metal provisioning requires OS images that can be deployed to physical hardware or VMs. These images must be prepared with necessary software (Kubernetes, cloud-init, container runtime) and optimized for PXE/network boot deployment. How should OS images be built to support Metal3 provisioning workflows while maintaining reproducibility and customization capabilities?

## Decision Drivers

* Reproducibility - Consistent image builds from source definitions
* Distribution support - Support for enterprise Linux distributions (Fedora, RHEL-based)
* Customization - Ability to pre-install Kubernetes components and dependencies
* Metal3 compatibility - Images work with Ironic deployment
* Build automation - Scriptable image creation process
* Version control - Image definitions tracked in git
* Maintenance - Ongoing image updates and security patches

## Considered Options

* **Option 1**: KIWI image builder
* **Option 2**: Packer with cloud-init
* **Option 3**: Manual image creation (virt-customize)
* **Option 4**: Cloud/vendor-provided images
* **Option 5**: Image Builder (Fedora/RHEL tool)

## Decision Outcome

Chosen option: **"KIWI image builder"**, because it provides declarative, reproducible image building with strong support for enterprise Linux distributions, integrates well with Metal3/Ironic workflows, and allows complete customization of image contents while maintaining image definitions in version control.

The implementation uses:
- KIWI image descriptions in XML (declarative image definition)
- Fedora-based images with Kubernetes components pre-installed
- OEM image type for bare metal deployment
- Cloud-init enabled for node customization
- Build scripts for automation and reproducibility

### Consequences

* Good, because declarative image definitions (XML config files)
* Good, because reproducible builds from source
* Good, because strong Fedora/openSUSE/RHEL support
* Good, because Metal3/Ironic compatible image format
* Good, because complete customization (packages, configs, scripts)
* Good, because image definitions in version control
* Good, because supports multiple image types (OEM, virtual, live)
* Bad, because XML-based configuration (learning curve)
* Bad, because less common than Packer in cloud-native ecosystems
* Bad, because build process requires privileged operations
* Neutral, because focused on Linux distributions (not multi-platform)

### Confirmation

This decision is validated through operational experience:
1. KIWI images successfully built with Kubernetes components
2. Images deployed via Metal3/Ironic to bare metal nodes
3. Cloud-init functioning correctly for node customization
4. Reproducible builds from git-tracked image descriptions
5. Image updates working (package updates, new Kubernetes versions)
6. Multiple image profiles supported (different Kubernetes configurations)

## Pros and Cons of the Options

### Option 1: KIWI image builder

* Good, because declarative image definitions
* Good, because reproducible builds
* Good, because excellent Linux distribution support
* Good, because Metal3/Ironic compatible
* Good, because complete customization capability
* Good, because image descriptions version-controllable
* Good, because supports OEM images for bare metal
* Bad, because XML configuration format
* Bad, because less mainstream than Packer
* Bad, because requires privileged build environment
* Neutral, because Linux-focused (matches use case)

### Option 2: Packer with cloud-init

* Good, because widely adopted in cloud-native space
* Good, because HCL/JSON configuration (familiar to many)
* Good, because multi-platform support
* Good, because large community and ecosystem
* Bad, because focused on cloud/VM images
* Bad, because less optimized for bare metal deployment
* Bad, because may require additional tooling for Metal3 compatibility
* Neutral, because capable but not specialized for this use case

### Option 3: Manual image creation (virt-customize)

* Good, because direct control over image creation
* Good, because flexible (any customization possible)
* Good, because simple concept
* Bad, because not reproducible (manual steps)
* Bad, because not declarative (imperative commands)
* Bad, because difficult to version control
* Bad, because error-prone (manual operations)
* Bad, because doesn't scale (hard to maintain multiple image variants)

### Option 4: Cloud/vendor-provided images

* Good, because no build infrastructure needed
* Good, because vendor-maintained and updated
* Good, because standard images
* Bad, because limited customization
* Bad, because not optimized for bare metal Kubernetes
* Bad, because Kubernetes components not pre-installed
* Bad, because may include unnecessary cloud-specific components
* Bad, because external dependency (image availability)

### Option 5: Image Builder (Fedora/RHEL tool)

* Good, because official Fedora/RHEL tool
* Good, because supports custom images
* Good, because blueprint-based configuration
* Bad, because less flexible than KIWI
* Bad, because limited to specific distributions
* Bad, because newer tool (less mature)
* Bad, because less comprehensive feature set than KIWI
* Neutral, because viable alternative but more limited

## More Information

This decision was made based on requirements for:
- Reproducible bare metal OS image creation
- Pre-installation of Kubernetes components
- Metal3/Ironic compatibility
- Version-controlled image definitions
- Support for Fedora and RHEL-based distributions

KIWI image description structure:
```xml
<?xml version="1.0" encoding="utf-8"?>
<image schemaversion="7.5" name="fedora-k8s-image">
    <description type="system">
        <author>Author Name</author>
        <contact>email@example.com</contact>
        <specification>Fedora Kubernetes Node Image</specification>
    </description>
    <preferences>
        <version>1.0.0</version>
        <packagemanager>dnf</packagemanager>
        <type image="oem" filesystem="ext4" kernelcmdline="console=ttyS0"/>
    </preferences>
    <packages type="image">
        <package name="kernel"/>
        <package name="cloud-init"/>
        <package name="kubernetes"/>
        <package name="containerd"/>
        <!-- Additional packages -->
    </packages>
</image>
```

Image build workflow:
1. Define image in KIWI XML description
2. Specify packages, configurations, scripts
3. Run KIWI build (kiwi-ng system build)
4. Output: Deployable OS image for Metal3
5. Store image on netboot server HTTP endpoint
6. Metal3 deploys image to bare metal nodes

Pre-installed components:
- **Kubernetes**: kubeadm, kubelet, kubectl
- **Container runtime**: containerd or CRI-O
- **Cloud-init**: For node-specific customization
- **Network tools**: For BMH networkData processing
- **System packages**: Required dependencies and utilities

Image profiles:
- Different profiles for different Kubernetes versions
- Profiles for different hardware configurations
- Testing vs production image variants
- All defined in same image description with profile selectors

Build automation:
- Wrapper scripts for repeatable builds
- CI/CD integration for automated image creation
- Version tagging aligned with Kubernetes releases
- Build artifacts stored for deployment

Image deployment:
- KIWI OEM images compatible with Ironic deployment
- Images served via HTTP from netboot server
- Metal3 references image URL in BareMetalHost spec
- Ironic deploys image to disk during provisioning

Image updates:
- Update packages in KIWI description
- Rebuild image
- Update image URL in Metal3 configuration
- Reprovision nodes with new image

Security considerations:
- Minimal package set (reduce attack surface)
- Regular rebuilds for security updates
- No secrets in base image (use cloud-init)
- Immutable base image approach

Related decisions:
- ADR-0000: Bare Metal Provisioning Approach (Metal3 deploys images)
- ADR-0003: Netboot Server for PXE Provisioning (serves built images)
- ADR-0007: Network Configuration Approach (cloud-init processes networkData)
