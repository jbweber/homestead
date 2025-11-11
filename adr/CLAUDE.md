# ADR Writing Guidelines for Claude

This file provides context for AI assistants helping to write Architecture Decision Records (ADRs) for this project.

## Purpose

We are documenting the architectural decisions made while building a bare metal Kubernetes cluster provisioning stack using Cluster API and Metal3. These ADRs should serve as:

1. **Historical record** - Why we made specific architectural choices
2. **Template foundation** - Basis for creating an implementation guide that others can follow
3. **Reusable knowledge** - Generic enough to apply beyond our specific environment

## Writing Principles

### ADR Best Practices (from adr.github.io)

**Definition of Ready (START)** - Before writing an ADR, the decision should be:
- **S**ignificant - Important enough to document
- **T**imely - Made at the right point in the project
- **A**ctionable - Clear what needs to be done
- **R**elevant - Matters to stakeholders
- **T**estable - Can be validated

**Definition of Done** - A complete ADR includes:
1. **Evidence** backing the choice
2. **Criteria and alternatives** documented
3. **Team agreement** (in our case, user approval)
4. **Proper documentation** completed
5. **Realization and review plan** established

### Our Specific Guidelines

**Keep It Generic**:
- Avoid environment-specific references (homelab, VM testing environment, etc.)
- Use generic terms like "small-scale deployment" or "resource-constrained environment"
- Focus on architectural tradeoffs, not implementation details
- Make decisions applicable to both testing and production scenarios

**Evidence-Based**:
- Reference actual experience (e.g., "validated through end-to-end reprovisioning test")
- Link to upstream documentation and issues
- Explain tradeoffs with concrete pros/cons
- Document what was learned, not just what was chosen

**Structure**:
- Follow the MADR template (see TEMPLATE.md)
- Keep context concise (2-3 sentences)
- List decision drivers as bullet points
- Provide detailed pros/cons for each option
- Include confirmation/validation methods

**Status**:
- All current ADRs are `status: accepted` (already implemented and validated)
- These are retrospective documentation of decisions already made
- Future decisions start as `status: proposed`

## Content Sources

When writing ADRs, reference these existing documents:

### Core Documentation
- `../capi/TODO.md` - Design decisions log, lessons learned
- `../docs/cilium-install.md` - Cilium deployment patterns
- `../docs/kube-vip-design.md` - kube-vip architecture
- `../docs/bootstrap-to-gitops.md` - GitOps transition strategy
- `../PLAN_HOMESTEAD.md` - Current status and outcomes

### Avoid Specific References
- DO NOT reference specific hostnames (metal3.cofront.xyz, super, capi-1)
- DO NOT reference specific IP addresses (10.250.250.x, 192.168.x.x)
- DO NOT reference specific hardware/VM configurations
- DO reference the _pattern_ or _approach_ generically

## Example: Good vs Bad Phrasing

**Bad** (too specific):
> We deployed a single-node cluster named "super" on metal3.cofront.xyz in our homelab to manage VMs provisioned via libvirt.

**Good** (generic, reusable):
> A single-node management cluster provides sufficient capacity for small-scale deployments while minimizing resource overhead. This approach works well when managing 2-5 workload clusters.

## Decision Sequence

The ADRs build on each other chronologically:

### Foundation Layer (0001-0003)
Decisions about the management infrastructure needed before any workload clusters can be created.

### Cluster API Layer (0004-0006)
Decisions about how to structure and deploy workload clusters.

### Networking Layer (0007-0009)
Decisions about network configuration and pod networking.

### Deployment & Tooling (0010-0011)
Decisions about how components are deployed and maintained.

## Cross-Referencing

ADRs should reference each other when decisions are related:
- Use "Related decisions:" section
- Explain how this decision builds on or affects other decisions
- Note when a decision supersedes a previous one

## Validation

Each ADR should include a "Confirmation" section describing how to validate the decision:
- Specific test scenarios
- Metrics or observations
- Success criteria
- What was actually observed in practice

## Review Process

1. Draft ADR following MADR template
2. Ensure it's generic (no environment-specific details)
3. Verify all options have detailed pros/cons
4. Include confirmation/validation method
5. Cross-reference related ADRs
6. User reviews and approves before finalizing
