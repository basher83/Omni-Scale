# Omni-Scale

Production-ready deployment kit for self-hosted [Sidero Omni](https://github.com/siderolabs/omni) with [Tailscale](https://tailscale.com) authentication.

## What This Does

Omni manages Talos Linux Kubernetes clusters. This repo provides everything needed to deploy Omni with:

- **Tailscale-only access** — no public exposure, no port forwarding
- **tsidp for authentication** — login with your Tailscale identity (OIDC)
- **Proxmox infrastructure provider** — automatic Talos VM provisioning
- **Production-ready configs** — systemd services, Docker Compose, troubleshooting docs

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                         Your Tailnet                            │
│                                                                 │
│  ┌─────────────┐      ┌─────────────┐      ┌────────────────┐  │
│  │   Browser   │─────▶│    tsidp    │◀─────│     Omni       │  │
│  │             │      │   (OIDC)    │      │  (K8s mgmt)    │  │
│  └─────────────┘      └─────────────┘      └────────────────┘  │
│        │                                          │             │
│        │            HTTPS via Tailscale           │             │
│        └──────────────────────────────────────────┘             │
│                                                                 │
│                              │                                  │
│                              ▼                                  │
│                    ┌──────────────────┐                        │
│                    │   Talos Nodes    │                        │
│                    │  (Kubernetes)    │                        │
│                    └──────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

| Component | Purpose | Deployment |
|-----------|---------|------------|
| **tsidp** | OIDC identity provider using Tailscale identities | Standalone VM, systemd |
| **Omni** | Kubernetes cluster lifecycle management | Docker Compose with Tailscale sidecar |
| **Proxmox provider** | Creates/destroys Talos VMs in Proxmox | Docker Compose (same stack as Omni) |
| **Talos nodes** | Kubernetes clusters managed by Omni | VMs provisioned by Omni via provider |

## Repository Structure

```text
.
├── tsidp/                  # Tailscale IdP (OIDC provider)
│   ├── README.md           # Installation guide
│   ├── TROUBLESHOOTING.md  # Common issues
│   ├── initial-install.sh  # Fresh install script
│   └── update-systemd.sh   # Update existing install
│
├── docker/                 # Omni + Proxmox provider deployment
│   ├── README.md           # Docker Compose setup
│   ├── TROUBLESHOOTING.md  # Common issues
│   ├── compose.yaml        # Docker Compose config
│   ├── .env.example        # Environment template
│   └── config.yaml.example  # Proxmox provider config template
│
└── docs/                   # Supplemental guides
    └── gpg-key-setup.md    # GPG key for Omni encryption
```

## Quick Start

### 1. Deploy tsidp

Provision a lightweight VM (Debian 13, 1 vCPU, 1GB RAM) and run:

```bash
# Get a Tailscale auth key from https://login.tailscale.com/admin/settings/keys
sudo ./tsidp/initial-install.sh tskey-auth-XXXXX
```

See [tsidp/README.md](tsidp/README.md) for details.

### 2. Configure Tailscale ACLs

Add the required grant for tsidp in your [Tailscale ACLs](https://login.tailscale.com/admin/acls/file):

```json
"grants": [
  {
    "src": ["*"],
    "dst": ["*"],
    "app": {
      "tailscale.com/cap/tsidp": [{
        "users": ["*"],
        "resources": ["*"],
        "allow_admin_ui": true,
        "allow_dcr": true,
        "extraClaims": { "email_verified": true },
        "includeInUserInfo": true
      }]
    }
  }
]
```

### 3. Generate GPG Key

Omni requires a GPG key for etcd encryption:

```bash
gpg --quick-generate-key "Omni (etcd encryption) <you@example.com>" rsa4096 cert never
gpg --quick-add-key <FINGERPRINT> rsa4096 encr never
gpg --export-secret-keys --armor <FINGERPRINT> > docker/omni.asc
```

See [docs/gpg-key-setup.md](docs/gpg-key-setup.md) for details and troubleshooting.

### 4. Deploy Omni

Provision a VM (Ubuntu 24.04, 2 vCPU, 4GB RAM) with Docker installed:

```bash
cd docker
cp .env.example .env
# Edit .env with your tsidp credentials
docker compose up -d
```

See [docker/README.md](docker/README.md) for details.

### 5. Access Omni

Navigate to `https://omni.<your-tailnet>.ts.net` and authenticate with Tailscale.

## Prerequisites

- **Tailscale account** with admin access
- **Two VMs** on your Tailnet:
  - tsidp: Debian 13+, 1 vCPU, 1GB RAM, systemd
  - Omni: Ubuntu 24.04, 2 vCPU, 4GB RAM, Docker
- **Tailscale auth key** from [admin console](https://login.tailscale.com/admin/settings/keys)

## Key Gotchas

| Issue | Solution |
|-------|----------|
| tsidp and Omni on same host | Don't. Networking conflicts between tsnet and host Tailscale. |
| "Invalid JWT" on login | Add `extraClaims: { "email_verified": true }` to ACL grant |
| `docker compose down -v` | Avoid `-v` flag—deletes Tailscale state, causes hostname collisions |

See component-specific `TROUBLESHOOTING.md` files for more.

## References

- [Sidero Omni Documentation](https://docs.siderolabs.com/omni/)
- [tsidp Repository](https://github.com/tailscale/tsidp)
- [Tailscale Docker Guide](https://tailscale.com/kb/1282/docker)
- [Omni + tsidp Guide](https://docs.siderolabs.com/omni/security-and-authentication/oidc-login-with-tailscale)

## License

MIT
