# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Omni-Scale is a production deployment kit for self-hosted Sidero Omni (Kubernetes cluster management) with Tailscale-only access and tsidp for OIDC authentication. This is an infrastructure-as-code repository containing configuration files, shell scripts, and Docker Compose definitions.

## Architecture

The system runs two separate components that must be on different hosts:

1. **tsidp** (Tailscale Identity Provider) - Runs as a systemd service on a dedicated VM (Debian). Provides OIDC authentication using Tailscale identities. Cannot share a host with Omni due to tsnet networking conflicts.

2. **Omni Stack** (Docker Compose) - Runs on a separate VM (Ubuntu with Docker):
   - `omni-tailscale`: Sidecar container providing Tailscale connectivity and HTTPS termination
   - `omni`: The Omni application for Kubernetes cluster lifecycle management
   - `proxmox-provider`: Infrastructure provider that creates/destroys Talos VMs in Proxmox

All containers in the Omni stack share the Tailscale container's network namespace (`network_mode: service:omni-tailscale`), which is why proxy targets in the serve config use `127.0.0.1`.

## Key Files

```
docker/
  compose.yaml          # Docker Compose stack definition
  .env                  # Environment variables (gitignored, copy from .env.example)
  config.yaml           # Proxmox provider config (gitignored, copy from config.yaml.example)
  omni.asc              # GPG key for Omni etcd encryption (gitignored)

tsidp/
  initial-install.sh    # Fresh install: sudo ./initial-install.sh tskey-auth-XXXXX
  update-systemd.sh     # Update existing install with current config
```

## Common Operations

### tsidp (on dedicated VM)

```bash
# Fresh install
sudo ./tsidp/initial-install.sh tskey-auth-XXXXX

# View logs
sudo journalctl -u tsidp -f

# Restart after config change
sudo systemctl restart tsidp
```

### Omni Stack (on Docker host)

```bash
cd docker

# Start
docker compose up -d

# View logs (all services or specific)
docker compose logs -f
docker compose logs -f proxmox-provider

# Restart specific service (preserves Tailscale state)
docker compose restart omni

# Stop (SAFE - preserves volumes)
docker compose down

# Full reset (DESTRUCTIVE - deletes Tailscale state, causes hostname collisions)
docker compose down -v
```

## Critical Gotchas

- **tsidp and Omni on same host**: Don't. Networking conflicts between tsnet and host Tailscale.
- **`docker compose down -v`**: Avoid `-v` flag. Deletes Tailscale state, causing hostname collisions (`omni-1`, `omni-2`). If you must reset, remove old devices from Tailscale admin console first.
- **"Invalid JWT" on login**: Add `extraClaims: { "email_verified": true }` to the Tailscale ACL grant.
- **Changing tsidp hostname**: Creates a NEW Tailscale node; delete old one from admin console.
- **OMNI_INITIAL_USER**: Must match the exact email from OIDC. Check login screen for the actual email.

## Tailscale ACL Grant (Required)

This grant must be added at https://login.tailscale.com/admin/acls/file:

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

## Environment Variables (docker/.env)

| Variable | Description |
|----------|-------------|
| `TS_AUTHKEY` | Tailscale auth key (must be reusable) |
| `OMNI_DOMAIN` | Omni hostname (e.g., `omni.tailnet.ts.net`) |
| `OMNI_INITIAL_USER` | First admin email (must match OIDC exactly) |
| `OIDC_ISSUER_URL` | tsidp URL (e.g., `https://tsidp.tailnet.ts.net`) |
| `OIDC_CLIENT_ID` | From tsidp admin UI or DCR |
| `OIDC_CLIENT_SECRET` | From tsidp admin UI or DCR |
| `OMNI_INFRA_PROVIDER_KEY` | Generated in Omni UI after first login |
