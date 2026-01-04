# Omni-Scale

Self-hosted Sidero Omni deployment kit with Tailscale authentication and Proxmox infrastructure provider.

## What This Does

Omni-Scale deploys Sidero Omni for managing Talos Linux Kubernetes clusters on Proxmox
infrastructure. The architecture separates the control plane (Omni Hub) from the VM
provisioner (Proxmox Provider), connected via Tailscale.

```text
┌─────────────────────────┐         ┌─────────────────────────┐
│  Quantum Cluster        │         │  Matrix Cluster         │
│  (Management Plane)     │         │  (Workloads)            │
│                         │         │                         │
│  ┌───────────────────┐  │ Tailscale  ┌───────────────────┐  │
│  │   Omni Hub        │◄─┼─────────┼──►│ Proxmox Provider  │  │
│  │   (Docker)        │  │         │  │ (LXC Container)   │  │
│  └───────────────────┘  │         │  └─────────┬─────────┘  │
│                         │         │            │            │
└─────────────────────────┘         │  ┌─────────▼─────────┐  │
                                    │  │   Talos VMs       │  │
                                    │  │ (K8s Nodes)       │  │
                                    │  └───────────────────┘  │
                                    └─────────────────────────┘
```

The Provider sits on the same L2 network as Talos VMs — this is required for SideroLink registration during boot.

## Prerequisites

- Proxmox VE cluster with shared storage (CEPH or similar)
- Tailscale account with MagicDNS enabled
- Auth0 tenant (or other OIDC provider)
- Domain with DNS control (Cloudflare recommended for cert automation)
- Docker and Docker Compose on the Hub host

## Quick Start

```bash
git clone https://github.com/youruser/Omni-Scale.git
cd Omni-Scale
```

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the full installation runbook.

## Project Structure

```text
├── omni/                    # Omni Hub deployment
│   ├── compose.yml          # Docker Compose for Hub + Tailscale sidecar
│   └── omni.env.example     # Environment configuration template
├── proxmox-provider/        # Proxmox infrastructure provider
│   ├── compose.yml          # Docker Compose for Provider
│   └── config.yaml.example  # Provider configuration template
├── clusters/                # Cluster templates (Omni format)
│   ├── talos-prod-01.yaml   # Production cluster (3 CP + 2 workers)
│   └── test-cluster.yaml    # Minimal test cluster
├── machine-classes/         # VM sizing definitions
│   ├── matrix-control-plane.yaml
│   ├── matrix-worker.yaml
│   └── examples/            # Additional examples (GPU, multi-disk)
├── docs/
│   ├── DEPLOYMENT.md        # Installation runbook
│   ├── OPERATIONS.md        # Day-to-day management
│   ├── TROUBLESHOOTING.md   # Issue resolution guide
│   └── guides/
│       └── CILIUM.md        # CNI installation post-bootstrap
├── scripts/
│   └── proxmox-vm-optimize.sh  # VM disk/GPU optimization
└── specs/
    └── omni.yaml            # Infrastructure specification
```

## Key Components

### Omni Hub

The Hub runs as a Docker Compose stack with a Tailscale sidecar for external access. It
exposes ports on both the Tailscale interface and the LAN IP to support Split-Horizon DNS.

Configuration: `omni/omni.env.example`

### Proxmox Provider

An LXC container on the Proxmox cluster running the Sidero infrastructure provider. Must be
L2-adjacent to the Talos VMs it provisions.

Configuration: `proxmox-provider/config.yaml.example`

### Machine Classes

See [docs/references/providerdata-fields.md](docs/references/providerdata-fields.md) for the complete field reference.

Define VM specifications for auto-provisioning:

```yaml
# machine-classes/matrix-worker.yaml
spec:
  autoprovision:
    providerid: matrix-cluster
    providerdata: |
      cores: 8
      memory: 16384
      disk_size: 100
      network_bridge: vmbr0
      storage_selector: name == "vm_ssd"
```

### Cluster Templates

Multi-document YAML defining cluster configuration:

```yaml
kind: Cluster
name: talos-prod-01
kubernetes:
  version: v1.34.2
talos:
  version: v1.12.0
---
kind: ControlPlane
machineClass:
  name: matrix-control-plane
  size: 3
```

Deploy with: `omnictl cluster template sync -f clusters/talos-prod-01.yaml`

## Documentation

| Document | Purpose |
|----------|---------|
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Full installation runbook with prerequisites |
| [OPERATIONS.md](docs/OPERATIONS.md) | CLI tools, cluster management, day-2 operations |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Resolved issues and diagnostic commands |
| [CILIUM.md](docs/guides/CILIUM.md) | Post-bootstrap CNI installation |

## Critical Gotchas

These cost days of debugging. Don't repeat them.

### Split-Horizon DNS (The Four-Day Boss Fight)

Talos VMs must reach Omni via LAN IP during boot — they're not on Tailscale yet. If Proxmox
hosts use public DNS (1.1.1.1), VMs inherit it and resolve to the Tailscale IP they can't
reach.

**Fix**: Configure Proxmox hosts to use your local DNS server (Unifi/PiHole) which returns
the LAN IP for `omni.yourdomain.com`.

### Docker Compose Volumes

```bash
# NEVER DO THIS
docker compose down -v
```

The `-v` flag deletes Tailscale state. Your hostname becomes `omni-1` and you have to clean
up stale devices in the Tailscale admin.

### GPG Key Passphrase

Omni's GPG key for etcd encryption must have **no passphrase**. There's no interactive
prompt at container startup.

### Auth0 Domain Format

```bash
# CORRECT
--auth-auth0-domain=dev-xyz.us.auth0.com

# WRONG (causes https://https:// error)
--auth-auth0-domain=https://dev-xyz.us.auth0.com
```

### Proxmox Provider Hostname Bug

The upstream `omni-infra-provider-proxmox` injects a hostname config that conflicts with Omni's
hostname management. You need a patched build with the `configureHostname` step removed.

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for build instructions. Use the `:local-fix`
tag instead of `:latest`.

### Don't Migrate Talos VMs

Proxmox live migration breaks Talos node state. Even with CEPH shared storage, migration
preserves disk but destroys the node's identity/SideroLink relationship.

You'll hit "Cannot migrate with local CD/DVD" first (`qm set <VMID> --ide2 none` to remove),
but don't bother — migration will break the node anyway. Accept initial distribution or
destroy and recreate.

## Tools

The project uses [mise](https://mise.jdx.dev/) for tool management. Install mise, then:

```bash
mise install
```

Available tasks:

```bash
mise run changelog        # Update CHANGELOG.md
mise run markdown-lint    # Lint markdown files
mise run pre-commit-run   # Run pre-commit hooks
```

## References

- [Sidero Omni Documentation](https://omni.siderolabs.com/)
- [omni-infra-provider-proxmox](https://github.com/siderolabs/omni-infra-provider-proxmox)
- [PR #38: Node Pinning](https://github.com/siderolabs/omni-infra-provider-proxmox/pull/38) (contributed by this project)
- [Talos Linux](https://www.talos.dev/)

## License

MIT
