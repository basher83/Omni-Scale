# Machine Classes

Machine class definitions for Omni Proxmox provider autoprovisioning.

## Notable UI Fields Not in YAML

The Omni UI exposes additional optional fields when creating machine classes that may not appear in exported YAML:

| UI Field | YAML Field | Location | Default | Description |
|----------|------------|----------|---------|-------------|
| Node | `node` | providerdata | (empty) | Pin to specific Proxmox node. Empty allows any node. |
| Vlan | `vlan` | providerdata | 0 | VLAN tag for VM network interface. 0 = untagged. |
| Kernel Arguments | `kernelargs` | autoprovision | [] | Additional Talos boot arguments. |
| Initial Labels | `matchlabels` | spec | [] | Labels applied to machines for selection. |
| Use gRPC Tunnel | `grpctunnel` | providerdata | 0 | Connectivity option for machine communication. |

Note: `metavalues: []` is also available at the autoprovision level.

## Example

See `matrix-worker.yaml` for a working example with core required fields.
