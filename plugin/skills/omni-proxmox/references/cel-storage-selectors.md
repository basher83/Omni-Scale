# CEL Storage Selectors Reference

The Proxmox infrastructure provider uses CEL (Common Expression Language) to dynamically select storage pools for VM disk placement.

## Syntax

Storage selectors are simple CEL expressions that evaluate against each available storage pool:

```text
<condition>
```

The expression filters available storage pools and selects one that matches.

## Available Fields

Use these fields in selector conditions:

| Field | Type | Description | Example Values |
|-------|------|-------------|----------------|
| `name` | string | Storage pool name | `"local-lvm"`, `"vm_ssd"`, `"ceph-pool"` |
| `type` | string | Storage backend type | `"lvmthin"`, `"zfspool"`, `"rbd"`, `"dir"`, `"nfs"` |

## Common Patterns

### Select by Storage Type

**LVM-Thin (local fast storage):**

```text
type == "lvmthin"
```

**ZFS Pool:**

```text
type == "zfspool"
```

**CEPH/RBD (distributed storage):**

```text
type == "rbd"
```

**Directory storage:**

```text
type == "dir"
```

**NFS storage:**

```text
type == "nfs"
```

### Select by Name

Exact match on storage pool name:

```text
name == "vm_ssd"
```

Combine with type for safety:

```text
type == "rbd" && name == "vm_ssd"
```

### Multiple Conditions

**LVM-Thin with specific name:**

```text
type == "lvmthin" && name == "local-lvm"
```

**Either CEPH or ZFS:**

```text
type == "rbd" || type == "zfspool"
```

## CEL Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equals | `type == "rbd"` |
| `!=` | Not equals | `type != "dir"` |
| `&&` | Logical AND | `type == "rbd" && name == "vm_ssd"` |
| `\|\|` | Logical OR | `type == "rbd" \|\| type == "zfspool"` |

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
3. No typos in storage name

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
providerdata: |
  storage_selector: type == "rbd" && name == "vm_ssd"
```

**Local LVM for development:**

```yaml
providerdata: |
  storage_selector: type == "lvmthin"
```

**ZFS pool by name:**

```yaml
providerdata: |
  storage_selector: type == "zfspool" && name == "tank"
```
