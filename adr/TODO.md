# ADR TODO

This file tracks future architecture decisions that need investigation and documentation.

## Pending Decisions

### Heterogeneous Infrastructure Providers

**Context**: Current stack uses CAPM3 (Metal3) exclusively for bare metal provisioning. Need to investigate how Cluster API supports mixing infrastructure providers within a single management cluster.

**Investigation needed**:
- Can a single CAPI management cluster manage workload clusters across multiple infrastructure providers (CAPM3 + CAPV/CAPZ/etc)?
- What are the operational implications of multi-provider management?
- How does this affect management cluster architecture decisions (single-node vs HA)?
- Are there resource or complexity tradeoffs for multi-provider vs separate management clusters per provider?

**Motivation**: Understanding multi-provider capabilities would inform:
- ADR-0001 (Management Cluster Architecture) - whether HA is needed for managing diverse infrastructure
- Future expansion beyond bare metal (VMs, cloud instances)
- Disaster recovery and migration strategies

**References**:
- [CAPI Multi-tenancy](https://cluster-api.sigs.k8s.io/user/concepts.html#multi-tenancy)
- [CAPI Provider Implementations](https://cluster-api.sigs.k8s.io/reference/providers.html)

### Future Topics

- Image building and distribution strategy (KIWI vs alternatives)
- Secrets management approach (current: manual kubectl, future: External Secrets Operator?)
- Observability stack selection (Prometheus/Grafana deployment pattern)
- Service mesh evaluation (Cilium service mesh vs Istio/Linkerd)
