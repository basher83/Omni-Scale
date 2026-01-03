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

| Component | Location | IP | Endpoint |
|-----------|----------|-----|----------|
| Omni | Holly (VMID 101, Quantum) | 192.168.10.20 | https://omni.spaceships.work |
| Auth0 OIDC | Managed | — | Auth0 tenant |
| Proxmox Provider | Foxtrot LXC (CT 200, Matrix) | 192.168.3.10 | L2 adjacent to Talos VMs |
| Target Cluster | Matrix (Foxtrot/Golf/Hotel) | 192.168.3.{5,6,7} | https://192.168.3.5:8006 |
| Storage | CEPH RBD | — | `vm_ssd` pool |

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Tailnet                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Quantum Cluster (192.168.10.0/24)       Matrix Cluster (192.168.3.0/24)   │
│   ┌───────────────────────────┐           ┌─────────────────────────────┐   │
│   │  Holly (VMID 101)         │           │  Foxtrot                    │   │
│   │  ┌─────────────────────┐  │           │  ┌───────────────────────┐  │   │
│   │  │  Docker Stack       │  │           │  │  LXC CT 200           │  │   │
│   │  │  ├─ omni-tailscale  │  │◄─────────►│  │  ├─ worker-tailscale  │  │   │
│   │  │  └─ omni            │  │  Tailnet  │  │  └─ proxmox-provider  │  │   │
│   │  └─────────────────────┘  │           │  └───────────────────────┘  │   │
│   │           │               │           │             │               │   │
│   │  LAN: 192.168.10.20       │           │    LAN: 192.168.3.10        │   │
│   └───────────────────────────┘           │             │               │   │
│              │                            │             ▼ L2 Adjacent   │   │
│              ▼                            │  ┌───────────────────────┐  │   │
│   ┌───────────────────────────┐           │  │  Proxmox API          │  │   │
│   │  Auth0 (External)         │           │  │  (Foxtrot/Golf/Hotel) │  │   │
│   │  OIDC Provider            │           │  └───────────────────────┘  │   │
│   └───────────────────────────┘           │             │               │   │
│                                           │             ▼               │   │
│   ┌───────────────────────────┐           │  ┌───────────────────────┐  │   │
│   │  Browser                  │──────────►│  │  Talos VMs            │  │   │
│   │  (Admin UI via Tailscale) │           │  │  (CEPH vm_ssd)        │  │   │
│   └───────────────────────────┘           │  └───────────────────────┘  │   │
│                                           └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key architectural decisions:**

| Decision | Rationale |
|----------|-----------|
| Omni on Holly (Quantum) | Separation of management plane from workload plane |
| Provider on Foxtrot LXC | L2 adjacency required for SideroLink registration |
| Auth0 for OIDC | Managed service, simpler than self-hosted tsidp |
| CEPH storage | Distributed storage across Matrix nodes |

**L2 Adjacency Requirement:**

The Proxmox provider must be network-adjacent to Talos VMs for SideroLink machine registration. When a Talos VM boots, it broadcasts on the local network to find the Omni control plane. The provider on Foxtrot LXC (192.168.3.10) shares L2 with Talos VMs on the Matrix cluster (192.168.3.x).

**Split-Horizon DNS:**

Talos VMs resolve `omni.spaceships.work` via Unifi local DNS to 192.168.10.20 (Holly's LAN IP). Static routing between 192.168.3.0/24 and 192.168.10.0/24 enables cross-subnet SideroLink registration.

## Provider Configuration

The Proxmox provider runs as Docker containers inside the `omni-provider` LXC (CT 200) on Foxtrot.

**File locations:**

| File | Purpose |
|------|---------|
| `proxmox-provider/compose.yml` | Docker Compose for provider + Tailscale sidecar |
| `proxmox-provider/config.yaml` | Proxmox API credentials (gitignored) |
| `proxmox-provider/.env` | Environment variables (gitignored) |

**Setup:**

```bash
# Copy example files
cp proxmox-provider/config.yaml.example proxmox-provider/config.yaml
cp proxmox-provider/.env.example proxmox-provider/.env

# Edit with actual credentials
vim proxmox-provider/config.yaml  # Proxmox API token
vim proxmox-provider/.env         # Tailscale key, Omni service account

# Deploy
cd proxmox-provider
docker compose up -d
```

### Provider Config (config.yaml)

```yaml
proxmox:
  url: "https://192.168.3.5:8006/api2/json"
  tokenID: "terraform@pam!automation"
  tokenSecret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  insecureSkipVerify: true  # Self-signed Proxmox certs
```

For Proxmox API token setup, see `references/proxmox-permissions.md`.

## MachineClass Structure

MachineClasses define VM specifications for auto-provisioning. Apply via omnictl.

```yaml
metadata:
  namespace: default
  type: MachineClasses.omni.sidero.dev
  id: matrix-worker
spec:
  autoprovision:
    providerid: matrix-cluster
    providerdata: |
      cores: 4
      sockets: 1
      memory: 16384
      disk_size: 100
      network_bridge: vmbr0
      storage_selector: name == "vm_ssd"
      node: foxtrot  # Pin to specific node (requires PR #38)
```

**Required providerdata fields:**

| Field | Description |
|-------|-------------|
| `cores` | Number of CPU cores |
| `sockets` | Number of CPU sockets |
| `memory` | RAM in megabytes |
| `disk_size` | Disk size in gigabytes |
| `network_bridge` | Proxmox network bridge (vmbr0 for Matrix) |
| `storage_selector` | CEL expression selecting Proxmox storage pool |

**Optional providerdata fields:**

| Field | Description |
|-------|-------------|
| `node` | Pin VM to specific Proxmox node (requires PR #38) |
| `disk_ssd` | Enable SSD emulation (true/false) |
| `disk_discard` | Enable TRIM/discard (true/false) |
| `cpu_type` | CPU type (default: x86-64-v2-AES, use "host" for GPU) |

## CEL Storage Selectors

The provider uses CEL (Common Expression Language) to select storage pools.

**Available fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Storage pool name |

> **Warning:** The `type` field is NOT usable — `type` is a reserved CEL keyword. Use `name` for all storage selection.

**Matrix cluster storage:**

```text
# CEPH RBD pool (recommended)
name == "vm_ssd"

# Container storage
name == "vm_containers"
```

For complete CEL syntax, see `references/cel-storage-selectors.md`.

## omnictl CLI

**Service account key (automation):**

```bash
omnictl --omni-url https://omni.spaceships.work \
        --service-account-key $OMNICTL_SERVICE_ACCOUNT_KEY \
        get clusters
```

**OIDC browser flow (interactive):**

```bash
# Any command triggers browser auth if not authenticated
omnictl get clusters
```

**Common operations:**

```bash
# List machine classes
omnictl get machineclasses

# Apply machine class
omnictl apply -f machine-classes/matrix-worker.yaml

# Sync cluster template
omnictl cluster template sync -f clusters/talos-prod-01.yaml

# Check cluster status
omnictl cluster status talos-prod-01

# Get machines
omnictl get machines --cluster talos-prod-01
```

## Cluster Templates

Multi-document YAML defining cluster, control plane, and workers:

```yaml
kind: Cluster
name: talos-prod-01
kubernetes:
  version: v1.34.3
talos:
  version: v1.11.6
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
systemExtensions:
  - siderolabs/qemu-guest-agent
  - siderolabs/iscsi-tools
---
kind: Workers
machineClass:
  name: matrix-worker
  size: 2
systemExtensions:
  - siderolabs/qemu-guest-agent
  - siderolabs/iscsi-tools
```

See `clusters/talos-prod-01.yaml` for the full production template.

## Troubleshooting

### Provider not registering

```bash
# Check provider logs (on Foxtrot LXC)
ssh omni-provider docker logs -f proxmox-provider

# Verify Tailscale connectivity
ssh omni-provider docker exec worker-tailscale tailscale status
```

### Machines stuck in provisioning

```bash
# Check Proxmox for VM creation
pvesh get /nodes/foxtrot/qemu --output-format json | jq '.[] | {vmid, name, status}'

# Check provider logs for errors
ssh omni-provider docker logs --tail=50 proxmox-provider | grep -i error
```

### Storage selector not matching

```bash
# List available storage pools
pvesh get /storage --output-format json | jq '.[].storage'

# Test CEL expression (provider logs show evaluation)
# Look for: "no storage pools matched selector"
```

For more troubleshooting, see `references/troubleshooting.md`.

## Key Constraints

**Networking:**

- Provider MUST be L2 adjacent to Talos VMs (Foxtrot LXC on 192.168.3.x)
- Omni on Holly (192.168.10.20) reachable via static route
- Split-horizon DNS: `omni.spaceships.work` → 192.168.10.20 (LAN) or Tailscale IP (external)

**Provider limitations:**

- Single disk per VM (additional disks via PR #36)
- Node pinning requires PR #38 (or custom build)
- CEL `type` keyword reserved — use `name` only

**Storage:**

- Use CEPH `vm_ssd` pool for production VMs
- CEPH provides HA across Matrix nodes
- ~12TB usable capacity (replication factor 3)

## Reference Files

- `references/cel-storage-selectors.md` — CEL syntax and patterns
- `references/proxmox-permissions.md` — API token setup
- `references/omnictl-auth.md` — Authentication methods
- `references/troubleshooting.md` — Common issues

## Example Files

- `examples/machineclass-ceph.yaml` — MachineClass with CEPH storage
- `examples/machineclass-local.yaml` — MachineClass with local LVM
- `examples/cluster-template.yaml` — Complete cluster template
