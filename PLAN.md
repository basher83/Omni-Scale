# Omni-Scale Plugin Plan

## Overview

Create a Claude Code plugin for managing Sidero Omni + Proxmox infrastructure provider deployments. This plugin provides commands, skills, and state management for the complete deployment lifecycle.

**Plugin name:** `omni-scale`

**Repository:** This repo (Omni-Scale)

**Reference:** Use [plugin-dev](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/plugin-dev) to scaffold.

---

## Plugin Structure

```text
Omni-Scale/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── provider/
│   │   ├── setup.md
│   │   ├── verify.md
│   │   └── status.md
│   ├── machineclass/
│   │   ├── create.md
│   │   └── apply.md
│   └── cluster/
│       ├── create.md
│       └── status.md
├── skills/
│   └── omni-proxmox/
│       ├── SKILL.md
│       ├── references/
│       │   ├── cel-storage-selectors.md
│       │   ├── proxmox-permissions.md
│       │   └── troubleshooting.md
│       └── examples/
│           ├── machineclass-ceph.yaml
│           ├── machineclass-local.yaml
│           └── cluster-template.yaml
├── .claude/
│   └── omni-scale.local.md.example
└── PLAN.md (this file)
```

---

## Commands

### /provider-setup

**Purpose:** Configure the Proxmox infrastructure provider

**Allowed tools:** `Bash`, `Write`, `Read`

**Workflow:**

1. Check prerequisites (Omni running, Proxmox reachable)
2. Create `docker/config.yaml` from example if not exists
3. Prompt for `OMNI_INFRA_PROVIDER_KEY` if missing from `.env`
4. Restart docker compose stack
5. Verify provider registers in Omni logs
6. Update state file

**State updates:** `provider_configured: true`

**References skill:** `omni-proxmox/SKILL.md`

### /provider-verify

**Purpose:** Verify provider connectivity to both Omni and Proxmox

**Allowed tools:** `Bash`, `Read`

**Workflow:**

1. Check docker compose service health
2. Test Proxmox API connectivity via curl
3. Check provider logs for registration confirmation
4. Report status

### /provider-status

**Purpose:** Quick status check of provider

**Allowed tools:** `Bash`

**Workflow:**

1. `docker compose ps` for service status
2. `docker compose logs --tail=20 proxmox-provider` for recent logs

### /machineclass-create

**Purpose:** Interactive MachineClass creation

**Argument hint:** `[name]`

**Allowed tools:** `Write`, `Read`

**Workflow:**

1. Read state for storage selector
2. Prompt for CPU, memory, disk size
3. Generate MachineClass YAML
4. Save to `machine-classes/[name].yaml`
5. Offer to apply

**References skill:** `omni-proxmox/references/cel-storage-selectors.md`

### /machineclass-apply

**Purpose:** Apply MachineClass to Omni

**Argument hint:** `[name]`

**Allowed tools:** `Bash`, `Read`

**Workflow:**

1. Verify file exists
2. Run `omnictl apply -f machine-classes/[name].yaml`
3. Verify creation

### /cluster-create

**Purpose:** Create a Talos cluster using machine classes

**Argument hint:** `[cluster-name]`

**Allowed tools:** `Bash`, `Write`, `Read`

**Workflow:**

1. List available machine classes
2. Prompt for control plane count, worker count
3. Generate cluster template
4. Apply via `omnictl cluster template sync`

### /cluster-status

**Purpose:** Check cluster status

**Argument hint:** `[cluster-name]`

**Allowed tools:** `Bash`

**Workflow:**

1. `omnictl get clusters`
2. `omnictl get machines --cluster [name]`

---

## Skills

### omni-proxmox/SKILL.md

**Description:** Core knowledge for Omni + Proxmox infrastructure provider. Use when deploying Talos clusters via Omni on Proxmox, creating machine classes, troubleshooting provider issues, or working with CEL storage selectors.

**Content outline:**

- Architecture overview (Omni → Provider → Proxmox → Talos VMs)
- Provider configuration basics
- MachineClass structure and fields
- Common operations
- Links to references and examples

### omni-proxmox/references/cel-storage-selectors.md

**Content:** CEL expression reference for storage selection

Include from existing `docker/config.yaml.example`:

- `storage.filter(s, s.type == "rbd" ...)` for CEPH
- `storage.filter(s, s.type == "lvmthin" ...)` for LVM
- `storage.filter(s, s.type == "zfspool" ...)` for ZFS
- Available fields: `s.storage`, `s.type`, `s.enabled`, `s.active`, `s.avail`

### omni-proxmox/references/proxmox-permissions.md

**Content:** Proxmox user/token setup for production

Include:

- Creating dedicated user
- Required permissions (VM.Allocate, VM.Config.*, Datastore.*)
- API token creation
- Token format for config.yaml

### omni-proxmox/references/troubleshooting.md

**Content:** Common issues and solutions

Include:

- Provider can't reach Proxmox API
- Storage selector returns empty
- VM creation fails
- Provider doesn't register with Omni

### omni-proxmox/examples/machineclass-ceph.yaml

```yaml
apiVersion: infrastructure.omni.siderolabs.io/v1alpha1
kind: MachineClass
metadata:
  name: matrix-worker
spec:
  type: auto-provision
  provider: proxmox
  config:
    cpu: 4
    memory: 8192
    diskSize: 40
    storageSelector: 'storage.filter(s, s.type == "rbd" && s.storage == "vm_ssd")[0].storage'
```

### omni-proxmox/examples/machineclass-local.yaml

```yaml
apiVersion: infrastructure.omni.siderolabs.io/v1alpha1
kind: MachineClass
metadata:
  name: local-worker
spec:
  type: auto-provision
  provider: proxmox
  config:
    cpu: 2
    memory: 4096
    diskSize: 20
    storageSelector: 'storage.filter(s, s.type == "lvmthin" && s.enabled && s.active)[0].storage'
```

### omni-proxmox/examples/cluster-template.yaml

```yaml
# Cluster template example - customize for your environment
kind: Cluster
name: my-cluster
kubernetes:
  version: v1.31.0
talos:
  version: v1.9.0
patches:
  - name: cluster-patches
    inline:
      cluster:
        network:
          cni:
            name: none  # For Cilium
controlPlane:
  machineClass: matrix-control
  count: 3
workers:
  machineClass: matrix-worker
  count: 3
```

---

## State Management

### .claude/omni-scale.local.md.example

```markdown
---
# Deployment state - copy to .claude/omni-scale.local.md
provider_configured: false
proxmox_endpoint: "https://192.168.3.5:8006/api2/json"
omni_endpoint: "https://omni.spaceships.work"
storage_selector: 'storage.filter(s, s.type == "rbd" && s.storage == "vm_ssd")[0].storage'
default_cpu: 4
default_memory: 8192
default_disk: 40
---

# Omni-Scale Deployment State

## Current Status
- Provider: Not configured
- Machine Classes: None
- Clusters: None

## Next Steps
1. Generate infrastructure provider key in Omni UI
2. Run /provider-setup
3. Run /provider-verify
4. Create machine classes with /machineclass-create
```

**Gitignore:** Add `.claude/*.local.md` to `.gitignore`

---

## Integration Points

### Existing Documentation

Commands and skills should reference existing repo docs:

- `docker/README.md` - Docker Compose setup
- `docker/TROUBLESHOOTING.md` - Common issues
- `docker/config.yaml.example` - Provider config reference
- `tsidp/README.md` - OIDC setup
- `docs/gpg-key-setup.md` - GPG key generation
- `DEPLOYMENT.md` - Deployment-specific details (gitignored)

### External References

- [mitchross/sidero-omni-talos-proxmox-starter](https://github.com/mitchross/sidero-omni-talos-proxmox-starter)
- [Sidero Omni Documentation](https://docs.siderolabs.com/omni/)
- [omni-infra-provider-proxmox](https://github.com/siderolabs/omni-infra-provider-proxmox)

---

## Implementation Notes

### For Claude Code

1. Use `plugin-dev` plugin to scaffold structure
2. Commands should be concise, reference skills for details
3. Skills contain the deep knowledge, examples contain copy-paste YAML
4. State file tracks deployment progress across sessions
5. All commands should read state first, update state on completion

### Tool Restrictions

- Provider commands: Need `Bash` for docker compose, curl
- MachineClass commands: Primarily `Write` and `Read`, `Bash` for omnictl
- Cluster commands: Need `Bash` for omnictl

### Error Handling

Commands should:

- Check prerequisites before proceeding
- Provide clear error messages
- Suggest next steps on failure
- Never leave state in inconsistent condition

---

## Acceptance Criteria

- [ ] Plugin loads in Claude Code without errors
- [ ] `/provider-setup` successfully configures provider
- [ ] `/provider-verify` confirms connectivity
- [ ] `/machineclass-create` generates valid YAML
- [ ] `/machineclass-apply` successfully applies to Omni
- [ ] `/cluster-create` provisions VMs in Proxmox
- [ ] State persists across sessions
- [ ] Skills provide useful context for troubleshooting
