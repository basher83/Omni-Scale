# CEL Storage Selectors Reference

The Proxmox infrastructure provider uses CEL (Common Expression Language) to dynamically select storage pools for VM disk placement.

## Syntax

Basic selector pattern:

```text
storage.filter(s, <condition>)[0].storage
```

The expression filters available storage pools, selects the first match, and returns its name.

## Available Fields

Use these fields in filter conditions:

| Field | Type | Description | Example Values |
|-------|------|-------------|----------------|
| `s.storage` | string | Storage pool name | `"local-lvm"`, `"vm_ssd"`, `"ceph-pool"` |
| `s.type` | string | Storage backend type | `"lvmthin"`, `"zfspool"`, `"rbd"`, `"dir"`, `"nfs"` |
| `s.enabled` | bool | Storage is enabled in Proxmox | `true`, `false` |
| `s.active` | bool | Storage is currently active | `true`, `false` |
| `s.avail` | int | Available space in bytes | `107374182400` (100GB) |
| `s.total` | int | Total space in bytes | `214748364800` (200GB) |
| `s.used` | int | Used space in bytes | `107374182400` (100GB) |

## Common Patterns

### Select by Storage Type

**LVM-Thin (local fast storage):**

```text
storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage
```

**ZFS Pool:**

```text
storage.filter(s, s.type == "zfspool" && s.enabled && s.active)[0].storage
```

**CEPH/RBD (distributed storage):**

```text
storage.filter(s, s.type == "rbd" && s.enabled && s.active)[0].storage
```

**Directory storage:**

```text
storage.filter(s, s.type == "dir" && s.enabled && s.active)[0].storage
```

**NFS storage:**

```text
storage.filter(s, s.type == "nfs" && s.enabled && s.active)[0].storage
```

### Select by Name

Exact match on storage pool name:

```text
storage.filter(s, s.storage == "vm_ssd")[0].storage
```

Combine with type for safety:

```text
storage.filter(s, s.type == "rbd" && s.storage == "vm_ssd")[0].storage
```

### Select by Capacity

Storage with most free space:

```text
storage.filter(s, s.enabled && s.active).max(s, s.avail).storage
```

Storage with at least 100GB free:

```text
storage.filter(s, s.enabled && s.active && s.avail > 107374182400)[0].storage
```

## CEL Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equals | `s.type == "rbd"` |
| `!=` | Not equals | `s.type != "dir"` |
| `&&` | Logical AND | `s.enabled && s.active` |
| `\|\|` | Logical OR | `s.type == "rbd" \|\| s.type == "zfspool"` |
| `>` | Greater than | `s.avail > 107374182400` |
| `<` | Less than | `s.used < s.total / 2` |

## Debugging

### List Available Storage

Check what storage pools exist on Proxmox:

```bash
# On Proxmox node
pvesh get /storage

# Or via API
curl -k https://proxmox:8006/api2/json/storage \
  -H "Authorization: PVEAPIToken=user@realm!tokenid=secret"
```

### Test Selector Logic

If a selector returns empty, verify:

1. Storage pool exists with expected name
2. Storage type matches (lvmthin vs lvm vs zfspool)
3. Storage is both enabled AND active
4. No typos in storage name

### Common Issues

**Empty result:**

The selector matched no storage pools. Check storage type spelling and pool name.

**Wrong storage selected:**

Multiple pools matched the filter. Add more specific conditions (e.g., by name).

**Type mismatch:**

Common confusion: `lvm` vs `lvmthin` vs `zfspool`. Check actual type via `pvesh get /storage`.

## Examples in MachineClass

**CEPH storage for HA workloads:**

```yaml
config:
  storageSelector: 'storage.filter(s, s.type == "rbd" && s.storage == "vm_ssd")[0].storage'
```

**Local LVM for development:**

```yaml
config:
  storageSelector: 'storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage'
```

**ZFS with minimum capacity:**

```yaml
config:
  storageSelector: 'storage.filter(s, s.type == "zfspool" && s.avail > 53687091200)[0].storage'
```
