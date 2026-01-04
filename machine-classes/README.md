# Machine Classes

Machine class definitions for Omni Proxmox provider autoprovisioning.

## Current Classes

| Class | Node Pinning | Purpose |
|-------|--------------|---------|
| `matrix-control-plane` | None (provider chooses) | Control plane nodes (3) |
| `matrix-worker-golf` | `node: golf` | Worker pinned to Golf |
| `matrix-worker-hotel` | `node: hotel` | Worker pinned to Hotel |

## Node Pinning Constraint

**Workers:** Can be pinned to specific nodes via separate `Workers` sections in cluster template.

**Control Planes:** Cannot be pinned. Omni requires exactly 1 `kind: ControlPlane` section per cluster template, so all CPs must use the same machine class. The Provider distributes them (currently all land on one node).

```
# This fails with "template should contain 1 controlplane, got 3"
kind: ControlPlane
machineClass:
  name: matrix-cp-foxtrot
  size: 1
---
kind: ControlPlane  # NOT ALLOWED
machineClass:
  name: matrix-cp-golf
  size: 1
```

See `docs/TROUBLESHOOTING.md` → "Control Plane Node Distribution Cannot Be Pinned" for details.

## Provider Data Fields

See [docs/references/providerdata-fields.md](../docs/references/providerdata-fields.md) for the complete field reference.

**Quick reference (commonly used):**

| Field | Required | Description |
|-------|----------|-------------|
| `cores` | Yes | CPU cores |
| `sockets` | Yes | CPU sockets |
| `memory` | Yes | RAM in MB |
| `disk_size` | Yes | Disk in GB |
| `network_bridge` | Yes | Proxmox bridge (vmbr0) |
| `storage_selector` | Yes | CEL expression for storage pool |
| `node` | No | Pin to specific Proxmox node |
| `disk_ssd` | No | SSD emulation |
| `disk_discard` | No | TRIM support |
| `cpu_type` | No | CPU type (use `host` for passthrough) |

**Advanced options** (GPU, multi-disk, multi-NIC): See full reference.

## Example

See `matrix-worker-golf.yaml` for a working example with node pinning.
