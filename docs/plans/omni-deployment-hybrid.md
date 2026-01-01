# Omni Deployment Plan

**Generated:** 2026-01-01
**Spec:** specs/omni.yaml

---

## Problem

Deploy a production Talos Kubernetes cluster on the Matrix cluster using Sidero Omni. The management plane (Omni + Auth0) and infrastructure provider are operational; now need to provision the actual workload cluster.

## Solution

Create MachineClasses targeting CEPH storage, then deploy a 3 control plane + 2 worker Talos cluster on Matrix using Omni's declarative cluster management.

---

## Current State

| Component | Location | Status |
|-----------|----------|--------|
| Omni | Holly (omni.spaceships.work) | Operational |
| Auth0 OIDC | Managed service | Operational |
| Proxmox Provider | Foxtrot LXC (192.168.3.10) | Operational |
| Matrix cluster | Foxtrot/Golf/Hotel | Ready for VMs |
| Talos cluster | — | Not created |

**Phases 1-2 complete.** Provider relocated to Foxtrot, Auth0 migration done. Infrastructure is ready for cluster provisioning.

---

## Locked Decisions

| Decision | Value | Notes |
|----------|-------|-------|
| Omni location | Holly (Quantum) | Management plane separation |
| Target cluster | Matrix (Foxtrot/Golf/Hotel) | CEPH storage, 10GbE |
| Storage | CEPH RBD `vm_ssd` | `storage_selector: name == "vm_ssd"` |
| Provider ID | `Proxmox` | Must match MachineClass `providerid` |

---

## Constraints

| Constraint | Impact |
|------------|--------|
| CEL `type` reserved keyword | Cannot filter storage by type; use `name` only |
| GPG key no passphrase | Omni can't unlock at startup |
| Email exact match | OIDC email must match initial user exactly |

---

## Phase 3: First Cluster

**Status:** Not started
**Depends on:** Phase 1 (complete)
**Exit criteria:** 3 CP + 2 workers running; `kubectl get nodes` shows all Ready

### Gap Analysis

| Required | Current State | Gap |
|----------|---------------|-----|
| MachineClass for control plane (CEPH) | `matrix-worker.yaml` uses `local-lvm` | Need new class with `vm_ssd` |
| MachineClass for workers (CEPH) | Same file, wrong storage | Need spec update or new class |
| Cluster template | `test-cluster.yaml` exists (1 CP, 0 workers) | Need production config |

### Tasks

| # | Task | Notes |
|---|------|-------|
| 1 | Create `matrix-control-plane` MachineClass | 4 CPU, 8GB RAM, 40GB disk, `vm_ssd` |
| 2 | Update `matrix-worker` MachineClass | 8 CPU, 16GB RAM, 100GB disk, `vm_ssd` |
| 3 | Create cluster config `talos-prod-01.yaml` | 3 CP, 2 workers, Cilium prep |
| 4 | Apply MachineClasses via omnictl | `omnictl apply -f machine-classes/` |
| 5 | Apply cluster config | `omnictl cluster template sync -f clusters/talos-prod-01.yaml` |
| 6 | Monitor provisioning | Watch Omni UI for VM creation |
| 7 | Verify cluster health | All nodes Ready, cluster passes health check |

### Validation

```bash
# Verify MachineClasses registered
omnictl get machineclasses

# Monitor cluster provisioning
omnictl cluster status talos-prod-01

# Check node health after provisioning
omnictl cluster health talos-prod-01

# Get kubeconfig
omnictl kubeconfig talos-prod-01 -o ~/.kube/talos-prod-01.yaml

# Verify nodes
KUBECONFIG=~/.kube/talos-prod-01.yaml kubectl get nodes
```

### Risks

| Risk | Mitigation |
|------|------------|
| CEPH pool name differs | Verify `pvesh get /storage` shows `vm_ssd` exists |
| Matrix capacity | 5 VMs need ~40 cores, ~56GB RAM; Matrix has capacity |
| Network bridge mismatch | Confirm `vmbr0` exists on all Matrix nodes |

---

## Phase 4: Tailscale Integration

**Status:** Not started
**Depends on:** Phase 3
**Exit criteria:** Operator running; workload accessible via Tailscale hostname

| Task | Notes |
|------|-------|
| Deploy Tailscale Kubernetes Operator | Helm chart |
| Configure operator auth | Tailscale OAuth client or auth key |
| Expose test workload | Validate end-to-end connectivity |

---

## Definition of Done

- [x] Omni console accessible via Tailscale with Auth0 OIDC
- [x] Proxmox Provider can create/destroy VMs on Matrix cluster
- [ ] Talos VMs successfully register with Omni on boot
- [ ] At least one Talos cluster (3 CP + 2 worker) operational
- [ ] Cluster survives single node failure
- [ ] Tailscale Kubernetes Operator deployed for workload access

---

## Next Action

**Phase:** 3
**Task:** Create MachineClass for control plane nodes targeting CEPH storage
**Command:**

```bash
# Create machine-classes/matrix-control-plane.yaml with:
cat > machine-classes/matrix-control-plane.yaml << 'EOF'
metadata:
  namespace: default
  type: MachineClasses.omni.sidero.dev
  id: matrix-control-plane
spec:
  autoprovision:
    providerid: Proxmox
    providerdata: |
      cores: 4
      sockets: 1
      memory: 8192
      disk_size: 40
      network_bridge: vmbr0
      storage_selector: name == "vm_ssd"
EOF

# Then apply:
omnictl apply -f machine-classes/matrix-control-plane.yaml
```

---

## Critical Files

| File | Why Critical |
|------|--------------|
| `machine-classes/matrix-worker.yaml` | Needs storage selector update to `vm_ssd` |
| `clusters/test-cluster.yaml` | Base for production cluster template |
| `plugin/skills/omni-proxmox/examples/cluster-template.yaml` | Reference for Cilium/extension config |
| `specs/omni.yaml` | Source of truth for cluster sizing and decisions |
| `plugin/skills/omni-proxmox/references/cel-storage-selectors.md` | Storage selector syntax reference |
