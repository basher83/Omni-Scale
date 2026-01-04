# Roadmap

High-level trajectory for Omni-Scale infrastructure.

**Last Updated:** 2026-01-04

---

## Current Focus

**Cluster Redeploy** — Tear down, apply optimized machine classes, redeploy with Cilium.

---

## Near Term

| Priority | Item | Notes |
|----------|------|-------|
| 1 | Cluster redeploy | Optimized machine classes ready in `pending/` |
| 2 | Cilium CNI | Gateway API enabled |
| 3 | Storage solution | Longhorn vs Proxmox CSI — decision needed |
| 4 | Secrets management | External Secrets + Infisical (aligns with Ansible) |

---

## Medium Term

| Item | Notes |
|------|-------|
| GitOps | Flux or ArgoCD |
| Authentik | SSO/Identity |
| PowerDNS | Authoritative DNS for spaceships.work |
| Tailscale Operator | Workload access |
| Monitoring | Prometheus/Grafana or VictoriaMetrics |

---

## Backlog

- Network policies / pod security
- Backup strategy (Velero)
- GPU passthrough workloads
- Multi-cluster (Quantum as dev?)

---

## Constraints

- ControlPlane node pinning not possible (Omni template limitation)
- Provider requires local patched build (hostname bug)
- Single admin — recovery must be solo-executable

---

## Execution Details

See `specs/omni.yaml` for current phase implementation.
