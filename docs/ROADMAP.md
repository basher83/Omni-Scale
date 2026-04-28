# Roadmap

High-level trajectory for the Omni-managed Talos substrate.

**Last Updated:** 2026-04-28

---

## Current Focus

**Substrate hygiene** — Keep Omni, the Proxmox provider, machine classes,
cluster templates, and bootstrap handoff docs aligned with the checked-in
configuration.

---

## Near Term

| Priority | Item | Notes |
|----------|------|-------|
| 1 | Provider docs | Refresh deployment and operations docs against `proxmox-provider/compose.yml` and `config.yaml.example` |
| 2 | Omni docs | Refresh Omni Hub compose/env examples against `omni/compose.yml` and `omni/omni.env.example` |
| 3 | Cluster template docs | Replace stale generic examples with `clusters/talos-prod-01.yaml` and `clusters/test/test-cluster.yaml` |
| 4 | GitOps handoff | Keep only bootstrap pointers to `../mothership-gitops`; do not duplicate app/platform state |

---

## Medium Term

| Item | Notes |
|------|-------|
| Cilium MTU durability | Keep the Omni/Talos `siderolink` MTU requirement explicit here and in `../mothership-gitops/README.md` bootstrap commands |
| Pod-MTU regression signal | Define the substrate invariant: pod `eth0` MTU should be 1450. Implementation may live in `../mothership-gitops` if it becomes a monitored workload. |
| Provider lifecycle | Track whether the local `:local-fix` provider image can be replaced by an upstream release |
| Recovery drill | Keep disaster recovery solo-executable through cluster recreation and GitOps bootstrap handoff |

---

## Backlog

- Proxmox provider upstream replacement check
- Omni Hub backup/restore procedure
- Machine class validation examples
- GPU passthrough workloads
- Multi-cluster (Quantum as dev?)

---

## Constraints

- ControlPlane node pinning not possible (Omni template limitation)
- Provider requires local patched build (hostname bug)
- Single admin — recovery must be solo-executable

---

## Execution Details

Desired substrate state is represented by `clusters/`, `machine-classes/`,
`omni/`, and `proxmox-provider/`. Post-bootstrap platform state is owned by
`../mothership-gitops`.
