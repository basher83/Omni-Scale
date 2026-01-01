---
name: omni-proxmox
description: This skill should be used when the user asks to "create a machine class",
  "configure Proxmox provider", "debug provider registration", "set up CEL storage
  selectors", "troubleshoot Omni provider", "check provider status", "create a Talos
  cluster", or needs guidance on Omni + Proxmox infrastructure integration for Talos
  Kubernetes clusters.
---

# Omni + Proxmox Infrastructure Provider

This skill provides guidance for deploying and managing Talos Linux Kubernetes clusters via Sidero Omni with the Proxmox infrastructure provider.

## Current Deployment

| Component | Location | Endpoint |
|-----------|----------|----------|
| Omni | Holly (Quantum) | https://omni.spaceships.work |
| Auth0 OIDC | Managed | Auth0 tenant |
| Proxmox Provider | Foxtrot LXC (VMID 200) | omni-provider.tailfb3ea.ts.net |
| Target Cluster | Matrix (Foxtrot/Golf/Hotel) | https://192.168.3.5:8006 |
| Storage | CEPH RBD | `vm_ssd` pool |

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                          Tailnet                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Quantum Cluster (Management)        Matrix Cluster (Workload) │
│   ┌─────────────────────────┐        ┌────────────────────────┐ │
│   │  Holly                  │        │  Foxtrot               │ │
│   │  ┌───────────────────┐  │        │  ┌──────────────────┐  │ │
│   │  │  Docker Stack     │  │        │  │  LXC: omni-prov  │  │ │
│   │  │  ├─ tailscale     │  │◄──────►│  │  └─ provider     │  │ │
│   │  │  └─ omni          │  │        │  └──────────────────┘  │ │
│   │  └───────────────────┘  │        │           │            │ │
│   └─────────────────────────┘        │           ▼            │ │
│              │                       │  ┌──────────────────┐  │ │
│              ▼                       │  │  Proxmox API     │  │ │
│   ┌─────────────────────────┐        │  │  (Foxtrot node)  │  │ │
│   │  Auth0 (External)       │        │  └──────────────────┘  │ │
│   │  OIDC Provider          │        │           │            │ │
│   └─────────────────────────┘        │           ▼            │ │
│                                      │  ┌──────────────────┐  │ │
│   ┌─────────────────────────┐        │  │  Talos VMs       │  │ │
│   │  Browser                │───────►│  │  (CEPH storage)  │  │ │
│   └─────────────────────────┘        │  └──────────────────┘  │ │
│                                      └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Component responsibilities:**

| Component | Purpose |
|-----------|---------|
| Auth0 | OIDC identity provider (managed service) |
| omni-tailscale | Sidecar providing Tailscale connectivity and HTTPS termination |
| omni | Kubernetes cluster lifecycle management |
| proxmox-provider | Creates/destroys Talos VMs in Proxmox based on MachineClass definitions |

**Key architectural decisions:**

- Provider runs on Foxtrot (LXC) for L2 adjacency with Talos VMs
- Auth0 replaced tsidp for simpler operations
- Omni remains on Holly (Quantum) for management/workload separation

## Provider Configuration

The Proxmox provider runs as a Docker container inside the `omni-provider` LXC on Foxtrot.

**Deployed configuration:**

| Setting | Value |
|---------|-------|
| LXC Location | Foxtrot (VMID 200) |
| App Directory | `/opt/omni-provider` |
| Container Image | `ghcr.io/siderolabs/omni-infra-provider-proxmox:latest` |
| Provider ID | `Proxmox` |
| Omni Endpoint | `https://omni.spaceships.work/` |
| Proxmox API | `https://192.168.3.5:8006` |
| API Token | `terraform@pam!automation` |

### Provider Config (config.yaml)

Proxmox API credentials and connection settings:

```yaml
proxmox:
  url: "https://192.168.3.5:8006/api2/json"
  insecureSkipVerify: true  # Self-signed Proxmox certs

  # API Token authentication
  tokenID: "terraform@pam!automation"
  tokenSecret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

The provider authenticates to Omni using `OMNI_INFRA_PROVIDER_KEY` environment variable (generated in Omni UI under Settings → Infrastructure Providers).

For Proxmox API token setup, see `references/proxmox-permissions.md`.

## MachineClass Structure

MachineClasses define VM specifications for auto-provisioning. Apply via omnictl using COSI format.

```yaml
metadata:
  namespace: default
  type: MachineClasses.omni.sidero.dev
  id: worker-standard
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
```

**Required providerdata fields:**

| Field | Description |
|-------|-------------|
| `cores` | Number of CPU cores |
| `sockets` | Number of CPU sockets |
| `memory` | RAM in megabytes |
| `disk_size` | Disk size in gigabytes |
| `network_bridge` | Proxmox network bridge (e.g., vmbr0) |
| `storage_selector` | CEL expression selecting Proxmox storage pool |

## CEL Storage Selectors

The provider uses CEL (Common Expression Language) to dynamically select storage pools.

**Available fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Storage pool name |

> **Warning:** The `type` field (storage backend type like "rbd", "lvmthin") is NOT usable because `type` is a reserved CEL keyword. Use `name` for all storage selection.

**Common patterns:**

```text
# CEPH/RBD storage (Matrix cluster)
name == "vm_ssd"

# Local LVM-thin storage
name == "local-lvm"

# ZFS pool by name
name == "tank"
```

For complete CEL syntax and debugging tips, see `references/cel-storage-selectors.md`.

## omnictl CLI

The omnictl CLI manages Omni resources. Authentication options:

**Service account key (automation):**

```bash
omnictl --omni-url https://omni.spaceships.work \
        --service-account-key $OMNICTL_SERVICE_ACCOUNT_KEY \
        get clusters
```

**OIDC browser flow (interactive):**

```bash
omnictl --omni-url https://omni.spaceships.work login
```

For detailed authentication setup, see `references/omnictl-auth.md`.

**Common operations:**

```bash
# List machine classes
omnictl get machineclasses

# Apply machine class
omnictl apply -f machine-classes/worker.yaml

# List clusters
omnictl get clusters

# Get machines in cluster
omnictl get machines --cluster my-cluster

# Sync cluster template
omnictl cluster template sync -f cluster.yaml
```

## Cluster Templates

Cluster templates use multi-document YAML with separate documents for cluster, control plane, and workers:

```yaml
kind: Cluster
name: talos-prod-01
kubernetes:
  version: v1.34.2
talos:
  version: v1.12.0
patches:
  - name: disable-default-cni
    inline:
      cluster:
        network:
          cni:
            name: none    # Required for Cilium
        proxy:
          disabled: true  # Cilium replaces kube-proxy
---
kind: ControlPlane
machineClass:
  name: matrix-control-plane
  size: 3
---
kind: Workers
machineClass:
  name: matrix-worker
  size: 2
```

See `examples/cluster-template.yaml` for a complete example with system extensions.

## Common Operations Workflow

### Creating Clusters

1. Create MachineClass YAML defining VM specs (use `vm_ssd` storage selector)
2. Apply MachineClass: `omnictl apply -f machineclass.yaml`
3. Create cluster template YAML
4. Sync template: `omnictl cluster template sync -f cluster.yaml`
5. Monitor provisioning in Omni UI

### Checking Status

```bash
# Provider status (on Foxtrot LXC)
ssh omni-provider docker ps

# Provider logs
ssh omni-provider docker logs -f omni-provider-proxmox-provider-1

# Omni resources
omnictl get clusters
omnictl get machines
omnictl get infraproviders
```

## Key Constraints

**Networking:**

- Provider must be L2-adjacent to Talos VMs (SideroLink registration requirement)
- All components communicate via Tailscale encrypted tunnels
- Proxmox API must be reachable from the provider host

**Provider limitations:**

- Single disk per VM only
- Uses default Proxmox bridge for networking
- No automatic GPU passthrough
- CEL `type` keyword reserved - use `name` for storage selection

**State management:**

- Never use `docker compose down -v` on Holly (deletes Tailscale state)
- Provider key stored in environment (not version controlled)
- MachineClasses can be version controlled

## Troubleshooting

For operational issues (CEL not matching, cluster stuck, machines not registering), see `references/troubleshooting.md`.

For deployment issues (container won't start, networking), see `docker/TROUBLESHOOTING.md`.

## Additional Resources

### Reference Files

- **`references/cel-storage-selectors.md`** - Complete CEL syntax and patterns
- **`references/proxmox-permissions.md`** - Proxmox user setup for production
- **`references/omnictl-auth.md`** - Authentication methods for omnictl
- **`references/troubleshooting.md`** - Common operational issues

### Example Files

- **`examples/machineclass-ceph.yaml`** - MachineClass with CEPH storage
- **`examples/machineclass-local.yaml`** - MachineClass with local LVM storage
- **`examples/cluster-template.yaml`** - Complete cluster template

### External Documentation

- [Sidero Omni Documentation](https://docs.siderolabs.com/omni/)
- [Proxmox Infrastructure Provider](https://github.com/siderolabs/omni-infra-provider-proxmox)
- [Talos Linux](https://www.talos.dev/)
