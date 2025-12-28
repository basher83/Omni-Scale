---
name: machineclass-create
description: Create and apply a MachineClass for Proxmox VM provisioning
allowed-tools: Bash, Write, Read, Edit, AskUserQuestion
argument-hint: [name]
---

# Create MachineClass

Create a MachineClass YAML and apply it to Omni.

## Read Defaults

Read `${CLAUDE_PROJECT_DIR}/.claude/omni-scale.local.md` if it exists to get defaults:

- `storage_selector` - Default CEL storage selector
- `default_cores` - Default CPU cores
- `default_memory` - Default memory in MB
- `default_disk` - Default disk size in GB
- `network_bridge` - Default network bridge

If state file doesn't exist, use these defaults:

- Cores: 4
- Sockets: 1
- Memory: 8192 (8GB)
- Disk: 40GB
- Network bridge: vmbr0
- Storage selector: `type == "lvmthin"`

## Get Provider ID

Read `${CLAUDE_PROJECT_DIR}/.claude/omni-scale.local.md` for `provider_id`.

If not set, check available providers:

```bash
omnictl get infraproviders
```

Use the provider ID from the output (e.g., "Proxmox").

## Get MachineClass Name

If `$1` argument provided, use it as the name.

Otherwise, ask user for the MachineClass name.

Validate: name should be lowercase, alphanumeric with hyphens only.

## Gather Specifications

Ask user for VM specifications (offer defaults):

1. **CPU cores** - Number of cores (default from state or 4)
2. **Sockets** - Number of CPU sockets (default 1)
3. **Memory** - RAM in MB (default from state or 8192)
4. **Disk size** - Disk in GB (default from state or 40)
5. **Network bridge** - Proxmox network bridge (default vmbr0)
6. **Storage selector** - CEL expression (default from state)

For storage selector, explain:

- Common options: LVM-Thin, ZFS, CEPH/RBD
- Refer to `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/cel-storage-selectors.md` for patterns

## Generate YAML

Create MachineClass YAML using COSI format:

```yaml
metadata:
  namespace: default
  type: MachineClasses.omni.sidero.dev
  id: <name>
spec:
  autoprovision:
    providerid: <provider_id>
    providerdata: |
      cores: <cores>
      sockets: <sockets>
      memory: <memory>
      disk_size: <disk>
      network_bridge: <bridge>
      storage_selector: <selector>
```

## Save File

Save to `${CLAUDE_PROJECT_DIR}/machine-classes/<name>.yaml`.

Create the `${CLAUDE_PROJECT_DIR}/machine-classes/` directory if it doesn't exist.

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
omnictl --omni-url <endpoint> apply -f ${CLAUDE_PROJECT_DIR}/machine-classes/<name>.yaml
```

If authentication is required:

1. Check for `OMNICTL_SERVICE_ACCOUNT_KEY` environment variable (for automation)
2. Or suggest running `omnictl login` for interactive OIDC flow

Note: This is a separate service account from `OMNI_INFRA_PROVIDER_KEY` (used by the infrastructure provider). See `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/omnictl-auth.md` for setup.

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
