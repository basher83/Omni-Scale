# Provider Data Field Reference

Authoritative reference for Proxmox Provider `providerdata` fields.

**Source:** [PR #36 - Advanced VM Options](https://github.com/siderolabs/omni-infra-provider-proxmox/pull/36) (merged Dec 30, 2025)

---

## Field Summary

| Category | Fields |
|----------|--------|
| **Compute** | `cores`, `sockets`, `memory`, `cpu_type`, `machine_type`, `numa`, `hugepages`, `balloon` |
| **Storage** | `disk_size`, `storage_selector`, `disk_ssd`, `disk_discard`, `disk_iothread`, `disk_cache`, `disk_aio`, `additional_disks` |
| **Network** | `network_bridge`, `vlan`, `additional_nics` |
| **PCI** | `pci_devices` |
| **Placement** | `node` ([PR #38](https://github.com/siderolabs/omni-infra-provider-proxmox/pull/38)) |

---

## Compute Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cores` | int | *required* | CPU cores per socket |
| `sockets` | int | 1 | Number of CPU sockets |
| `memory` | int | *required* | RAM in MB |
| `cpu_type` | string | `x86-64-v2-AES` | CPU type. Use `host` for passthrough |
| `machine_type` | string | `i440fx` | VM machine type. Use `q35` for PCIe passthrough |
| `numa` | bool | false | Enable NUMA topology |
| `hugepages` | string | - | Hugepages size: `2`, `1024`, or `any` |
| `balloon` | bool | true | Enable memory ballooning. Disable for GPU/HPC |

---

## Storage Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `disk_size` | int | *required* | Primary disk size in GB |
| `storage_selector` | string | *required* | CEL expression for storage pool (use `name` only) |
| `disk_ssd` | bool | false | Enable SSD emulation |
| `disk_discard` | bool | false | Enable TRIM/discard support |
| `disk_iothread` | bool | false | Enable dedicated IO thread |
| `disk_cache` | string | - | Cache mode: `none`, `writeback`, `writethrough`, `directsync`, `unsafe` |
| `disk_aio` | string | - | AIO mode: `native`, `io_uring`, `threads` |

### Additional Disks

```yaml
additional_disks:
  - disk_size: 500
    storage_selector: name == "nvme-pool"
    disk_ssd: true
    disk_iothread: true
    disk_aio: io_uring
  - disk_size: 1000
    storage_selector: name == "hdd-archive"
    disk_cache: writeback
```

---

## Network Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `network_bridge` | string | `vmbr0` | Primary network bridge |
| `vlan` | int | 0 | VLAN tag (0 = untagged) |

### Additional NICs

```yaml
additional_nics:
  - bridge: vmbr1
    firewall: false
  - bridge: vmbr2
    vlan: 20
```

---

## PCI Passthrough

Requires Proxmox Resource Mappings configured.

```yaml
pci_devices:
  - mapping: nvidia-rtx-4090
    pcie: true
```

| Field | Type | Description |
|-------|------|-------------|
| `mapping` | string | Proxmox resource mapping name |
| `pcie` | bool | Use PCIe (requires `machine_type: q35`) |

---

## Placement Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `node` | string | - | Pin VM to specific Proxmox node |

**Note:** Node pinning only works for Workers (multiple `Workers` sections allowed). Control Planes cannot be pinned due to Omni template limitation (exactly 1 `ControlPlane` section required).

---

## Example Configurations

### Standard Worker (Current)

```yaml
providerdata: |
  cores: 8
  sockets: 1
  memory: 16384
  disk_size: 100
  network_bridge: vmbr0
  storage_selector: name == "vm_ssd"
  node: golf
  disk_ssd: true
  disk_discard: true
  cpu_type: host
```

### High-Performance GPU Worker

```yaml
providerdata: |
  cores: 24
  memory: 480000
  storage_selector: name == "ssdpool"
  cpu_type: host
  machine_type: q35
  numa: true
  balloon: false
  pci_devices:
    - mapping: nvidia-rtx-4090
      pcie: true
  disk_ssd: true
  disk_aio: io_uring
  disk_cache: none
```

### Multi-Disk Storage Node

```yaml
providerdata: |
  cores: 16
  memory: 64000
  disk_size: 100
  storage_selector: name == "fastpool"
  additional_disks:
    - disk_size: 500
      storage_selector: name == "nvme-pool"
      disk_ssd: true
      disk_iothread: true
      disk_aio: io_uring
    - disk_size: 1000
      storage_selector: name == "hdd-archive"
      disk_cache: writeback
```

### Multi-Homed Network Worker

```yaml
providerdata: |
  cores: 8
  memory: 32000
  disk_size: 200
  storage_selector: name == "ssdpool"
  disk_discard: true
  vlan: 10
  additional_nics:
    - bridge: vmbr1
      firewall: false
    - bridge: vmbr2
      vlan: 20
```

---

## Storage Selector Notes

CEL expression to select Proxmox storage pool. **Use `name` only** — `type` is a reserved CEL keyword.

```yaml
# Correct
storage_selector: name == "vm_ssd"

# WRONG - type is reserved
storage_selector: type == "rbd"
```
