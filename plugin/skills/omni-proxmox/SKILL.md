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

## Architecture Overview

The system consists of four components communicating over a Tailscale network:

```text
┌─────────────────────────────────────────────────────────────┐
│                        Your Tailnet                         │
├─────────────────────────────────────────────────────────────┤
│   ┌──────────────┐         ┌──────────────────────────┐    │
│   │    tsidp     │         │     Docker Stack         │    │
│   │  (OIDC)      │◄────────│  ┌──────────────────┐   │    │
│   │  separate VM │         │  │  omni-tailscale  │   │    │
│   └──────────────┘         │  │  (sidecar)       │   │    │
│                            │  └────────┬─────────┘   │    │
│   ┌──────────────┐         │  ┌────────▼─────────┐   │    │
│   │  Browser     │◄────────│  │      omni        │   │    │
│   └──────────────┘         │  └────────┬─────────┘   │    │
│                            │  ┌────────▼─────────┐   │    │
│                            │  │ proxmox-provider │   │    │
│                            │  └────────┬─────────┘   │    │
│                            └───────────│─────────────┘    │
└────────────────────────────────────────│──────────────────┘
                                         │ Proxmox API
                              ┌──────────▼──────────┐
                              │   Proxmox Cluster   │
                              │  (Talos VMs)        │
                              └─────────────────────┘
```

**Component responsibilities:**

| Component | Purpose |
|-----------|---------|
| tsidp | OIDC identity provider using Tailscale identities |
| omni-tailscale | Sidecar providing Tailscale connectivity and HTTPS termination |
| omni | Kubernetes cluster lifecycle management |
| proxmox-provider | Creates/destroys Talos VMs in Proxmox based on MachineClass definitions |

## Provider Configuration

The Proxmox provider requires two configuration files in the `docker/` directory:

### Environment Variables (.env)

Essential variables for the provider:

| Variable | Purpose |
|----------|---------|
| `OMNI_INFRA_PROVIDER_KEY` | Authentication key from Omni UI (Settings → Infrastructure Providers) |
| `OMNI_DOMAIN` | Omni hostname (e.g., `omni.your-tailnet.ts.net`) |

### Provider Config (config.yaml)

Proxmox API credentials and connection settings:

```yaml
proxmox:
  url: "https://<proxmox-node>:8006/api2/json"
  insecureSkipVerify: true  # For self-signed certs

  # Option 1: API Token (recommended)
  tokenID: "omni@pve!omni-provider"
  tokenSecret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  # Option 2: Username/password (testing only)
  # username: "root"
  # password: "your-password"
  # realm: "pam"
```

For production deployments, create a dedicated Proxmox user with limited permissions.
See `references/proxmox-permissions.md` for required permissions and setup commands.

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
      storage_selector: type == "rbd" && name == "vm_ssd"
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
| `type` | string | Storage type (lvmthin, zfspool, rbd, dir, nfs) |

**Common patterns:**

```text
# LVM-Thin storage
type == "lvmthin"

# CEPH/RBD storage by name
type == "rbd" && name == "vm_ssd"

# ZFS pool
type == "zfspool"

# Specific storage by name
name == "local-lvm"
```

For complete CEL syntax and debugging tips, see `references/cel-storage-selectors.md`.

## omnictl CLI

The omnictl CLI manages Omni resources. Authentication options:

**Service account key (automation):**

```bash
omnictl --omni-url https://omni.example.ts.net \
        --service-account-key $OMNICTL_SERVICE_ACCOUNT_KEY \
        get clusters
```

**OIDC browser flow (interactive):**

```bash
omnictl --omni-url https://omni.example.ts.net login
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

Cluster templates define the complete cluster configuration:

```yaml
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
  machineClass: control-plane
  count: 3
workers:
  machineClass: worker-standard
  count: 3
```

See `examples/cluster-template.yaml` for a complete example.

## Common Operations Workflow

### Initial Setup

1. Deploy tsidp on separate VM (see tsidp/README.md)
2. Configure Tailscale ACLs with `email_verified: true` claim
3. Deploy Omni stack via Docker Compose
4. Generate infrastructure provider key in Omni UI
5. Add key to `.env` as `OMNI_INFRA_PROVIDER_KEY`
6. Configure `config.yaml` with Proxmox credentials
7. Restart stack: `docker compose up -d`

### Creating Clusters

1. Create MachineClass YAML defining VM specs
2. Apply MachineClass: `omnictl apply -f machineclass.yaml`
3. Create cluster template YAML
4. Sync template: `omnictl cluster template sync -f cluster.yaml`
5. Monitor provisioning in Omni UI

### Checking Status

```bash
# Docker services
docker compose -f docker/compose.yaml ps

# Provider logs
docker compose -f docker/compose.yaml logs -f proxmox-provider

# Omni resources
omnictl get clusters
omnictl get machines
```

## Key Constraints

**Networking:**

- tsidp and Omni must run on separate hosts (tsnet conflicts)
- All components communicate via Tailscale encrypted tunnels
- Proxmox API must be reachable from the Omni host

**Provider limitations:**

- Single disk per VM only
- Uses default Proxmox bridge for networking
- No automatic GPU passthrough

**State management:**

- Never use `docker compose down -v` (deletes Tailscale state)
- Provider key stored in `.env` (gitignored)
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
