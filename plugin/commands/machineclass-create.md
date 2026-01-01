---
name: machineclass-create
description: Create and apply a MachineClass for Proxmox VM provisioning
allowed-tools: Bash, Write, Read, AskUserQuestion
argument-hint: [name]
---

# Create MachineClass

Create a MachineClass YAML and apply it to Omni.

## Omni Endpoint

```
https://omni.spaceships.work
```

## Defaults

Use these defaults for Matrix cluster (CEPH storage):

| Setting | Default | Notes |
|---------|---------|-------|
| Cores | 4 | Control plane; 8 for workers |
| Sockets | 1 | |
| Memory | 8192 | MB (8GB); 16384 for workers |
| Disk | 40 | GB; 100 for workers |
| Network bridge | vmbr0 | |
| Storage selector | `name == "vm_ssd"` | CEPH RBD pool |
| Provider ID | Proxmox | |

## Get MachineClass Name

If `$1` argument provided, use it as the name.

Otherwise, ask user for the MachineClass name.

Naming convention: `matrix-<role>` (e.g., `matrix-control-plane`, `matrix-worker`)

Validate: name should be lowercase, alphanumeric with hyphens only.

## Gather Specifications

Ask user for VM specifications (offer defaults):

1. **CPU cores** - Number of cores (default 4 for CP, 8 for workers)
2. **Memory** - RAM in MB (default 8192 for CP, 16384 for workers)
3. **Disk size** - Disk in GB (default 40 for CP, 100 for workers)
4. **Storage selector** - CEL expression (default `name == "vm_ssd"`)

For storage selector, explain:

- Matrix cluster uses CEPH: `name == "vm_ssd"`
- Local storage option: `name == "local-lvm"`
- Note: `type` field is reserved in CEL and cannot be used
- See `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/cel-storage-selectors.md`

## Generate YAML

Create MachineClass YAML using COSI format:

```yaml
metadata:
  namespace: default
  type: MachineClasses.omni.sidero.dev
  id: <name>
spec:
  autoprovision:
    providerid: Proxmox
    providerdata: |
      cores: <cores>
      sockets: 1
      memory: <memory>
      disk_size: <disk>
      network_bridge: vmbr0
      storage_selector: <selector>
```

## Save File

Save to `${CLAUDE_PROJECT_DIR}/machine-classes/<name>.yaml`.

Create the `${CLAUDE_PROJECT_DIR}/machine-classes/` directory if it doesn't exist.

Show the user the generated YAML.

## Check omnictl

Verify omnictl is available:

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

## Apply to Omni

Apply the MachineClass:

```bash
omnictl --omni-url https://omni.spaceships.work apply -f ${CLAUDE_PROJECT_DIR}/machine-classes/<name>.yaml
```

If authentication is required:

1. Check for `OMNICTL_SERVICE_ACCOUNT_KEY` environment variable
2. Or run `omnictl --omni-url https://omni.spaceships.work login` for interactive Auth0 flow

See `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/omnictl-auth.md` for setup.

## Verify Creation

List machine classes to confirm:

```bash
omnictl --omni-url https://omni.spaceships.work get machineclasses
```

## Summary

Report:

- MachineClass name and specs
- File location: `machine-classes/<name>.yaml`
- Apply status (success/failure)
- Next steps: Create cluster template or add more machine classes
