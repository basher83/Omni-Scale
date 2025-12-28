# OmniScale

## Overview

OmniScale deploys [Sidero Omni](https://github.com/siderolabs/omni)—a Kubernetes cluster management platform—behind [Tailscale](https://tailscale.com) for secure, private access. It uses Tailscale's tsidp as an OIDC identity provider, enabling authentication via your Tailscale account, and includes the Proxmox infrastructure provider for automatic Talos VM provisioning.

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                        Your Tailnet                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌──────────────┐         ┌──────────────────────────┐    │
│   │    tsidp     │         │     This Stack           │    │
│   │  (separate   │  OIDC   │  ┌──────────────────┐   │    │
│   │   machine)   │◄────────┼──│  omni-tailscale  │   │    │
│   │              │         │  │  (sidecar)       │   │    │
│   └──────────────┘         │  └────────┬─────────┘   │    │
│                            │           │network_mode │    │
│   ┌──────────────┐         │  ┌────────▼─────────┐   │    │
│   │  Your        │  HTTPS  │  │      omni        │   │    │
│   │  Browser     │◄────────┼──│                  │   │    │
│   │              │         │  └────────┬─────────┘   │    │
│   └──────────────┘         │           │             │    │
│                            │  ┌────────▼─────────┐   │    │
│                            │  │ proxmox-provider │   │    │
│                            │  │                  │   │    │
│                            │  └────────┬─────────┘   │    │
│                            └───────────│─────────────┘    │
└────────────────────────────────────────│──────────────────┘
                                         │ Proxmox API
                              ┌──────────▼──────────┐
                              │   Proxmox Cluster   │
                              │  ┌────┐ ┌────┐     │
                              │  │ VM │ │ VM │ ... │
                              │  └────┘ └────┘     │
                              └─────────────────────┘
```

### Component Responsibilities

| Container | Purpose |
|-----------|---------|
| **omni-tailscale** | Sidecar that connects to your Tailnet, provides HTTPS termination via Tailscale Serve, and handles MagicDNS resolution. All other containers share its network stack. |
| **omni** | The Omni application. Manages Talos Linux Kubernetes clusters. Uses OIDC for authentication. |
| **proxmox-provider** | Infrastructure provider that creates/destroys Talos VMs in Proxmox based on Omni machine class definitions. |
| **tsidp** (external) | Tailscale's OIDC identity provider. Runs on a separate machine. Issues JWT tokens for authentication. |

### Network Flow

1. User browses to `https://omni.your-tailnet.ts.net`
2. Request hits `omni-tailscale` via Tailscale
3. Tailscale Serve proxies to `omni:8080`
4. Omni redirects to tsidp for authentication
5. tsidp validates Tailscale identity, issues JWT
6. Omni validates JWT, grants access
7. When scaling clusters, Omni signals proxmox-provider
8. proxmox-provider calls Proxmox API to create/destroy VMs

## Prerequisites

### Accounts & Services

- **Tailscale account** with MagicDNS and HTTPS certificates enabled
- **tsidp** running on a separate machine (cannot run on same host due to networking conflicts)
- **GPG key** for Omni etcd encryption — see [GPG Key Setup](../docs/gpg-key-setup.md)
- **Proxmox cluster** with API access from the Omni host

### Tailscale ACL Configuration

Add this grant to your ACLs at <https://login.tailscale.com/admin/acls/file>:

```json
"grants": [
  {
    "src": ["*"],
    "dst": ["*"],
    "app": {
      "tailscale.com/cap/tsidp": [
        {
          "users": ["*"],
          "resources": ["*"],
          "allow_admin_ui": true,
          "allow_dcr": true,
          "extraClaims": {
            "email_verified": true
          },
          "includeInUserInfo": true
        }
      ]
    }
  }
]
```

> ⚠️ **Critical**: The `email_verified: true` claim is required. Without it, Omni rejects all logins with "invalid jwt".

### Generate Tailscale Auth Key

1. Go to <https://login.tailscale.com/admin/settings/keys>
2. Generate a new auth key
3. Select **Reusable** (required for container restarts)
4. Copy the key for `.env`

## Quick Start

1. **Required files**:
   - `compose.yaml`
   - `.env` (copy from `.env.example`)
   - `omni.asc` (GPG key)
   - `config.yaml` (copy from `config.yaml.example`)

2. **Configure `.env`**:

   ```bash
   cp .env.example .env
   ```

   Edit with your values:

   ```bash
   TS_AUTHKEY=tskey-auth-xxxxx
   OMNI_DOMAIN=omni.your-tailnet.ts.net
   OMNI_INITIAL_USER=you@example.com
   OIDC_ISSUER_URL=https://tsidp.your-tailnet.ts.net
   OIDC_CLIENT_ID=<from-tsidp>
   OIDC_CLIENT_SECRET=<from-tsidp>
   OMNI_INFRA_PROVIDER_KEY=<from-omni>
   ```

3. **Configure Proxmox provider**:

   ```bash
   cp config.yaml.example config.yaml
   ```

   Edit with your Proxmox credentials (see [Proxmox Provider Configuration](#proxmox-provider-configuration)).

4. **Start the stack**:

   ```bash
   docker compose up -d
   ```

5. **Access Omni** at `https://omni.your-tailnet.ts.net`

6. **Generate Infrastructure Provider key** (after first login):
   - Go to Omni UI → Settings → Infrastructure Providers
   - Create a new provider, copy the key
   - Add to `.env` as `OMNI_INFRA_PROVIDER_KEY`
   - Restart: `docker compose up -d`

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `TS_AUTHKEY` | Tailscale auth key. Must be **reusable**. |
| `OMNI_DOMAIN` | Your Omni hostname (e.g., `omni.tailnet.ts.net`) |
| `OMNI_INITIAL_USER` | First admin user email. Must match exact OIDC email. |
| `OIDC_ISSUER_URL` | tsidp URL (e.g., `https://tsidp.tailnet.ts.net`) |
| `OIDC_CLIENT_ID` | From tsidp admin UI or dynamic registration |
| `OIDC_CLIENT_SECRET` | From tsidp admin UI or dynamic registration |
| `OMNI_INFRA_PROVIDER_KEY` | Infrastructure provider key from Omni UI |

### Proxmox Provider Configuration

Create `config.yaml` from the example:

```yaml
proxmox:
  # Proxmox API URL - any node in the cluster
  url: "https://192.168.3.5:8006/api2/json"

  # Option 1: Username/password (testing)
  username: root
  password: "your-password"
  realm: "pam"

  # Option 2: API token (production)
  # tokenId: "omni@pam!omni-provider"
  # tokenSecret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  # Skip TLS verification (self-signed certs)
  insecureSkipVerify: true
```

#### Creating a Proxmox API Token (Production)

For production, create a dedicated user and API token with limited permissions:

```bash
# On Proxmox node
pveum user add omni@pam
pveum aclmod / -user omni@pam -role PVEVMAdmin
pveum user token add omni@pam omni-provider
```

Use the returned token ID and secret in `proxmox-provider.yaml`.

### compose.yaml

#### Tailscale Serve Config (Inline)

The Tailscale Serve configuration is embedded in `compose.yaml` using Docker Compose configs:

```yaml
configs:
  ts-serve:
    content: |
      {
        "TCP": {
          "443": { "HTTPS": true },
          "8090": { "HTTPS": true },
          "8100": { "HTTPS": true }
        },
        "Web": {
          "${TS_CERT_DOMAIN}:443": {
            "Handlers": { "/": { "Proxy": "http://127.0.0.1:8080" } }
          },
          ...
        }
      }
```

- **Port 443**: Web UI
- **Port 8090**: Machine API (Talos node communication)
- **Port 8100**: Kubernetes proxy

The `${TS_CERT_DOMAIN}` variable is automatically set by the Tailscale container to your MagicDNS hostname.

Proxy targets use `127.0.0.1` (loopback) because omni shares the tailscale container's network namespace. Both containers see the same localhost.

#### omni-tailscale Service

| Setting | Purpose | Why It's Needed |
|---------|---------|-----------------|
| `TS_USERSPACE=false` | Use kernel networking mode | Creates real `tailscale0` interface. Userspace mode doesn't configure DNS, breaking MagicDNS resolution. |
| `TS_ACCEPT_DNS=true` | Accept Tailscale DNS settings | Rewrites `/etc/resolv.conf` to use MagicDNS (100.100.100.100) |
| `TS_ENABLE_HEALTH_CHECK=true` | Enable `/healthz` endpoint | Allows Docker healthcheck to verify Tailscale is connected |
| `cap_add: NET_ADMIN, SYS_MODULE` | Linux capabilities | Required for creating tun device and managing routes |
| `devices: /dev/net/tun` | TUN device access | Required for kernel-mode Tailscale |
| `healthcheck` | Wait for Tailscale + DNS | Prevents omni from starting before MagicDNS is ready |

#### omni Service

| Setting | Purpose | Why It's Needed |
|---------|---------|-----------------|
| `network_mode: service:omni-tailscale` | Share tailscale's network | Gives omni access to Tailscale network and MagicDNS |
| `condition: service_healthy` | Wait for healthcheck | Ensures Tailscale is connected before omni starts |
| `--initial-users` | First admin user | Must match exact email from OIDC |
| `/dev/net/tun` mount | TUN device for siderolink | Omni's WireGuard-based machine communication |

#### proxmox-provider Service

| Setting | Purpose | Why It's Needed |
|---------|---------|-----------------|
| `network_mode: service:omni-tailscale` | Share tailscale's network | Provider needs MagicDNS to reach Omni API |
| `--omni-api-endpoint` | Omni API URL | Provider registers with and receives commands from Omni |
| `--omni-service-account-key` | Infrastructure provider key | Authentication to Omni (note: this is an *infra provider key*, not a service account) |
| `--config-file` | Proxmox connection config | Credentials and API endpoint for Proxmox |

## Creating Machine Classes

After the provider is running, create a MachineClass in Omni to define VM specs:

```yaml
apiVersion: infrastructure.omni.siderolabs.io/v1alpha1
kind: MachineClass
metadata:
  name: proxmox-worker
spec:
  type: auto-provision
  provider: proxmox
  config:
    cpu: 4
    memory: 8192          # MB
    diskSize: 40          # GB
    storageSelector: 'name == "vm_ssd"'
```

Apply via Omni UI or CLI. Then use in cluster manifests:

```yaml
spec:
  machineClass: proxmox-worker
  replicas: 3
```

## Gotchas

### 🔴 tsidp Cannot Run on Same Host as Omni

Running tsidp and omni-tailscale on the same machine causes networking conflicts. tsidp's embedded tsnet and the host/container Tailscale fight over routing. **Run tsidp on a separate machine.**

### 🔴 `docker compose down -v` Causes Hostname Collisions

The `-v` flag deletes volumes, including Tailscale state. On restart, Tailscale registers as a new device (`omni-1`, `omni-2`, etc.) because the old device still exists in admin console.

- **Fix**: Use `docker compose down` (no `-v`)
- **If you must reset**: Remove old devices from Tailscale admin console first

### 🔴 "Invalid JWT" / "Email Not Verified"

tsidp doesn't set `email_verified: true` by default. Omni requires it.

- **Fix**: Add the ACL grant with `extraClaims: { "email_verified": true }` (see Prerequisites)

### 🟡 "Identity Not Authorized for This Instance"

The `OMNI_INITIAL_USER` email doesn't match the OIDC email exactly.

- **Fix**: Check the exact email shown on login screen, update `OMNI_INITIAL_USER` in `.env`, delete `omni-data` volume, and restart

### 🟡 Omni Fails on First Start, Works After Restart

Race condition: omni starts before Tailscale DNS is ready.

- **Fix**: The healthcheck verifies both Tailscale connectivity AND MagicDNS resolution:
  ```yaml
  test: ["CMD-SHELL", "wget -q --spider http://localhost:9002/healthz && getent hosts controlplane.tailscale.com"]
  ```
- The `/healthz` endpoint only confirms Tailscale has an IP—not sufficient alone
- `getent hosts` proves DNS resolution actually works
- If you modify the healthcheck, ensure both checks are present

### 🟡 DNS Resolution Fails (lookup on 127.0.0.11)

Tailscale running in userspace mode doesn't configure MagicDNS.

- **Fix**: Ensure `TS_USERSPACE=false` and `/dev/net/tun` is mounted

### 🟡 Volume Permission Denied

Docker volumes created as root, but containers run as non-root users.

- **Fix**: `sudo chown -R <uid>:<gid> /var/lib/docker/volumes/<volume>/_data`
- tsidp uses UID 1001, check others with `docker run --rm <image> id`

### 🟡 Proxmox Provider: Resource ID Mismatch

Provider crashes with `resource ID must match the infra provider ID "Proxmox"`.

- **Fix**: Add `--id=Proxmox` to provider command in compose.yaml (capital P required)

### 🟡 Proxmox Provider: Storage Selector Required

During VM provisioning, you may see errors about missing storage selector.

- **Fix**: Add `storageSelector` to your MachineClass config:
  ```yaml
  config:
    storageSelector: 'name == "vm_ssd"'
  ```

### 🟡 Proxmox Provider: Cannot Reach Proxmox API

The provider can't connect to Proxmox.

- **Fix**: Ensure the Omni host can reach your Proxmox API (e.g., `192.168.3.5:8006`)
- The provider shares the Tailscale network namespace but still has access to the host's default route

## Useful Commands

```bash
# Start stack
docker compose up -d

# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f proxmox-provider

# Check container health
docker compose ps

# Restart omni only (preserves Tailscale state)
docker compose restart omni

# Restart provider after config change
docker compose restart proxmox-provider

# Stop without deleting volumes (SAFE)
docker compose down

# Full reset (DESTRUCTIVE - removes all data)
docker compose down -v
```

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for detailed solutions to common issues.

## Resources

- [Sidero Omni Documentation](https://docs.siderolabs.com/omni/)
- [Omni + tsidp Guide](https://docs.siderolabs.com/omni/security-and-authentication/oidc-login-with-tailscale)
- [Proxmox Infrastructure Provider](https://github.com/siderolabs/omni-infra-provider-proxmox)
- [Tailscale Docker Documentation](https://tailscale.com/kb/1282/docker)
- [tsidp Blog Post](https://tailscale.com/blog/building-tsidp)
