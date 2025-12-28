---
name: machineclass-create
description: Create and apply a MachineClass for Proxmox VM provisioning
allowed-tools: Bash, Write, Read, Edit, AskUserQuestion
argument-hint: [name]
---

# Create MachineClass

Create a MachineClass YAML and apply it to Omni.

## Read Defaults

Read `.claude/omni-scale.local.md` if it exists to get defaults:

- `storage_selector` - Default CEL storage selector
- `default_cpu` - Default CPU count
- `default_memory` - Default memory in MB
- `default_disk` - Default disk size in GB

If state file doesn't exist, use these defaults:

- CPU: 4
- Memory: 8192 (8GB)
- Disk: 40GB
- Storage selector: `storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage`

## Get MachineClass Name

If `$1` argument provided, use it as the name.

Otherwise, ask user for the MachineClass name.

Validate: name should be lowercase, alphanumeric with hyphens only.

## Gather Specifications

Ask user for VM specifications (offer defaults):

1. **CPU cores** - Number of vCPUs (default from state or 4)
2. **Memory** - RAM in MB (default from state or 8192)
3. **Disk size** - Disk in GB (default from state or 40)
4. **Storage selector** - CEL expression (default from state)

For storage selector, explain:

- Common options: LVM-Thin, ZFS, CEPH/RBD
- Refer to `skills/omni-proxmox/references/cel-storage-selectors.md` for patterns

## Generate YAML

Create MachineClass YAML:

```yaml
apiVersion: infrastructure.omni.siderolabs.io/v1alpha1
kind: MachineClass
metadata:
  name: <name>
spec:
  type: auto-provision
  provider: proxmox
  config:
    cpu: <cpu>
    memory: <memory>
    diskSize: <disk>
    storageSelector: '<selector>'
```

## Save File

Save to `machine-classes/<name>.yaml`.

Create the `machine-classes/` directory if it doesn't exist.

Show the user the generated YAML.

## Apply to Omni

Check if omnictl is available:

```bash
command -v omnictl || ls ~/.local/bin/omnictl
```

If not found, offer to download:

```bash
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
mkdir -p ~/.local/bin
curl -fsSL "https://github.com/siderolabs/omni/releases/latest/download/omnictl-${OS}-${ARCH}" -o ~/.local/bin/omnictl
chmod +x ~/.local/bin/omnictl
```

Read state file for `omni_endpoint`.

Apply the MachineClass:

```bash
omnictl --omni-url <endpoint> apply -f machine-classes/<name>.yaml
```

If authentication is required, check for `OMNICTL_SERVICE_ACCOUNT_KEY` environment variable or suggest running `omnictl login` first.

## Verify Creation

List machine classes to confirm:

```bash
omnictl --omni-url <endpoint> get machineclasses
```

## Summary

Report:

- MachineClass name and specs
- File location
- Apply status (success/failure)
- Next steps: Use in cluster template or create more machine classes
