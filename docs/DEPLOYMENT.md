# Sidero Omni Self-Hosting Runbook

**Project Name:** Omni-Scale
**Architecture:** Hub-and-Spoke (Path 1) with Split-Horizon DNS
**Version Target:** Omni v1.4.6+

---

## 0. Build Checklist

### Prerequisites (Complete Before Starting)

#### Tailscale Auth Keys

You need two separate keys: one for the Omni Hub (requires ACL tag) and one for the Worker.

**For the Omni Hub (Doggos/VM):**

1. Log in to the [Tailscale Admin Console](https://login.tailscale.com/admin)
2. Navigate to **Settings > Keys**
3. Click **Generate auth key**
4. Configure:
   - Description: `omni-hub`
   - Reusable: ✅ (recommended for Docker containers)
   - Ephemeral: ✅ (optional, good for containers)
   - Tags: Select `tag:omni` (create in Access Controls if it doesn't exist)
   - ⚠️ **Critical:** Your `docker-compose.yml` uses `TS_EXTRA_ARGS=--advertise-tags=tag:omni`. If the key is not pre-authorized for this tag, the container will fail to start.
5. Click **Generate** and copy to `omni.env` as `TS_AUTHKEY`

**For the Worker (Matrix/LXC):**

1. Click **Generate auth key** again
2. Configure:
   - Description: `proxmox-worker`
   - Reusable: ✅
   - Tags: None required
3. Copy to Worker's `.env` or `docker-compose.yml`

#### Cloudflare API Token

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to **My Profile > API Tokens**
3. Click **Create Token**
4. Use template: **Edit zone DNS**
5. Zone Resources: Include your domain (`spaceships.work`)
6. Save token for certbot DNS-01 challenge

#### Auth0 Configuration

**Application Setup:**

1. Log in to [Auth0 Dashboard](https://manage.auth0.com)
2. Navigate to **Applications > Applications**
3. Click **Create Application**
4. Name: `Sidero Omni`
5. Application Type: **Single Page Web Applications** (Omni uses PKCE flow)

**Settings Tab:**

| Setting | Value |
|---------|-------|
| Domain | Copy this (e.g., `dev-xyz.us.auth0.com`) |
| Client ID | Copy this |
| Allowed Callback URLs | `https://omni.spaceships.work` |
| Allowed Logout URLs | `https://omni.spaceships.work` |
| Allowed Web Origins | `https://omni.spaceships.work` |

**Connections:**

1. Navigate to **Connections** tab of your application
2. Enable at least one connection (e.g., `github`, `google-oauth2`)

⚠️ **The Major Gotcha:**

When adding to `omni.env`, do NOT include the protocol:

```bash
# ✅ CORRECT
--auth-auth0-domain=dev-so2wa1cutbtcbdi8.us.auth0.com

# ❌ INCORRECT (causes crash)
--auth-auth0-domain=https://dev-so2wa1cutbtcbdi8.us.auth0.com
```

The Omni binary automatically prepends `https://`. Including it yourself causes `https://https://...` errors.

#### Omni Account UUID

This is a random UUID v4 that you generate yourself (not provided by Sidero Labs):

```bash
uuidgen
# Output example: 851d71b7-8ccc-435a-809e-46f291d7168c
```

This acts as the unique identifier for your self-hosted installation.

#### GPG Encryption Key

To create the `omni.asc` file for etcd encryption:

```bash
# 1. Generate the key
gpg --quick-generate-key "Omni Etcd Encryption" default default never

# 2. Find the Key ID
gpg --list-keys
# Look for the long alphanumeric string under 'pub'

# 3. Export to file
gpg --export-secret-keys --armor <KEY_ID> > omni.asc
```

---

### Build Sequence

```text
┌─────────────────────────────────────────────────────────────────┐
│ Phase 0: External Services                                      │
│   Tailscale keys → Cloudflare API token → Auth0 tenant         │
│   UUID generation → GPG key                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: Omni Hub (Section 3.1)                                 │
│   VM → Tailscale → Certs → docker-compose up                   │
│                                                                 │
│   ✓ Gate: Can access https://omni.spaceships.work from         │
│           Tailnet device, login succeeds via Auth0              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1.5: Service Account                                      │
│   Omni UI → Settings → Service Accounts → Create                │
│                                                                 │
│   ⚠️  Copy key immediately—shown only once!                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 2: Worker (Section 3.2)                                   │
│   LXC → TUN config → docker-compose up                         │
│                                                                 │
│   ✓ Gate: Worker appears in Omni UI under Infrastructure       │
│           Providers, status = Connected (Green)                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 3: CLI & Cluster Setup (see OPERATIONS.md)                │
│   Install omnictl → Configure → Create Machine Classes          │
│                                                                 │
│   ✓ Gate: `omnictl get machineclasses` returns your classes    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 4: First Cluster                                          │
│   Sync Cluster Template → Watch VM provision                    │
│                                                                 │
│   ✓ Gate: VM boots, SideroLink shows ✓, node joins cluster     │
└─────────────────────────────────────────────────────────────────┘
```

---

### Phase 1.5: Create Service Account (Detailed)

1. Log in to Omni Dashboard (`https://omni.spaceships.work`)
2. Navigate to **Settings** (Gear Icon) → **Service Accounts**
3. Click **Create Service Account**
4. Name: `matrix-worker` or `proxmox-provider`
5. Role: Default (sufficient for Provider)
6. Click **Create**
7. ⚠️ **Copy the key immediately**—it is shown only once
8. Paste into Worker's `docker-compose.yml`:

   ```text
   --omni-service-account-key=[PASTE_KEY_HERE]
   ```

---

### Estimated Time

| Phase | Duration | Notes |
|-------|----------|-------|
| Phase 0: External Services | ~30 min | Mostly clicking through UIs |
| Phase 1: Omni Hub | ~1-2 hrs | Cert generation can be slow |
| Phase 1.5: Service Account | ~5 min | |
| Phase 2: Worker | ~30 min | Faster if you've done LXC TUN before |
| Phase 3: CLI & Machine Classes | ~15 min | See [OPERATIONS.md](./OPERATIONS.md) |
| Phase 4: First Cluster | ~15 min | Mostly waiting for VM boot |

---

### What Success Looks Like

**Dashboard State:**

- Cluster card shows **Green** status indicator
- Control Plane: `1/1` (node registered and joined)
- Health Metrics: `etcd`, `kube-apiserver`, `kubelet` all show **Healthy/Ready**

**SideroLink Status:**

- Connection column shows **Green Checkmark (✓)**
  - Previous failure state: Red "X" or "Connection Refused"
- Phase progression: `Registering` → `Installing` → `Running`
- IP Address: Node reports LAN IP (`192.168.3.x`), confirming local network communication

**Infrastructure Provider Status:**

- Location: **Infrastructure > Providers**
- Your provider (`matrix-cluster`) shows **Connected (Green)**
- Metadata displays Proxmox version and available resources

**"It's Working" Indicators:**

- The logs quiet down—no more `reconcile failed: resource Links... doesn't exist` loops
- Proxmox console shows VM booted and staying running (no reboot loop)
- VM successfully pulled its config from Omni

---

## 1. Prerequisites

### Infrastructure

- **Proxmox Virtual Environment:** 3-node cluster ("Matrix": Foxtrot, Golf, Hotel)
- **Storage:** Ceph (vm_ssd) for High Availability of Control Plane nodes
- **Network:**
  - A dedicated management VLAN/Subnet (e.g., 192.168.10.x)
  - A local DNS/DHCP server (Unifi Controller)

### External Services

- **Tailscale:** A generic Tailnet. MagicDNS enabled recommended.
- **Cloudflare:** Domain control for spaceships.work (used for DNS-01 SSL challenge and public resolution)
- **Auth0:** A tenant for OIDC authentication

---

## 2. Architecture Overview

### Topology

The setup uses a "Brain" (Hub) and "Hands" (Worker) model to manage resources across clusters.

| Component | Host Type | Location | Hostname | IP | Purpose |
|-----------|-----------|----------|----------|-----|---------|
| Omni Hub | Docker VM | Cluster A ("Doggos") | omni-host | 192.168.10.20 | Central Management Plane & UI |
| Worker | Docker LXC | Cluster B ("Matrix") | proxmox-worker-matrix | 192.168.3.10 | Proxmox Infrastructure Provider |
| Talos VMs | Virtual Machine | Cluster B ("Matrix") | (DHCP) | (DHCP) | Kubernetes Control Plane/Workers |

### Networking

- **External Access (Admin/Worker):** Traffic flows via Tailscale VPN
  - URL: `https://omni.spaceships.work` resolves to 100.x.y.z
- **Internal Access (Talos Nodes):** Traffic flows via Local LAN
  - URL: `https://omni.spaceships.work` resolves to 192.168.10.20
- **Bridge:** The Omni Hub container uses a Tailscale sidecar but explicitly maps ports to the Host LAN IP to allow local traffic entrance

### Authentication

- **Provider:** Auth0 (SaaS)
- **Flow:** Single Page Application (PKCE) flow
- **User Identity:** GitHub Social Connection

### DNS Architecture

DNS was the primary source of friction. The final architecture relies on Split-Horizon DNS to satisfy SSL requirements without exposing the Hub to the public internet.

**Public DNS (Cloudflare):**

- A Record: `omni.spaceships.work` → `100.89.181.31` (Tailscale IP of the Omni Sidecar)
- Purpose: Allows you (Admin) and the Worker (LXC) to connect securely from anywhere

**Local DNS (Unifi Controller):**

- Local DNS Record: `omni.spaceships.work` → `192.168.10.20` (LAN IP of Omni VM)
- Purpose: Allows Talos VMs to reach the Hub during boot without needing Tailscale keys

**Host DNS (Proxmox Nodes):**

- Configuration: All Proxmox nodes (Foxtrot, etc.) MUST use the Unifi Gateway IP (e.g., 192.168.10.1) as their DNS server
- Why: Talos VMs inherit DNS settings from the Proxmox host during the initial boot phase. If Proxmox uses 1.1.1.1, the VM resolves the Public IP (Tailscale), fails to route, and the boot hangs.

---

## 3. Installation & Configuration

### 3.1 Phase 1: The Omni Hub (Cluster A)

#### Host Setup (Ubuntu VM)

1. Install Tailscale binary (for SSH management). hostname: omni-host
2. Generate GPG keys (`gpg --quick-generate-key ...`)
3. Generate SSL Certs via Certbot + Cloudflare DNS-01 plugin

#### Configuration (omni.env)

> Note: Uses v1.4+ flag syntax.

```bash
OMNI_IMG_TAG=v1.4.6
OMNI_ACCOUNT_UUID=[UUID]
NAME=omni
EVENT_SINK_PORT=8091

# Certs
TLS_CERT=/etc/letsencrypt/live/omni.spaceships.work/fullchain.pem
TLS_KEY=/etc/letsencrypt/live/omni.spaceships.work/privkey.pem
ETCD_VOLUME_PATH=/etc/etcd/
ETCD_ENCRYPTION_KEY=/home/ansible/docker/omni/omni.asc

# Storage (Required v1.4+)
OMNI_SQLITE_PATH=/_out/etcd/omni.db

# Binding
BIND_ADDR=0.0.0.0:443
MACHINE_API_BIND_ADDR=0.0.0.0:8090
K8S_PROXY_BIND_ADDR=0.0.0.0:8100

# SideroLink (Internal LAN Access)
SIDEROLINK_ADVERTISED_API_URL="https://omni.spaceships.work:8090/"
SIDEROLINK_WIREGUARD_ADVERTISED_ADDR="192.168.10.20:50180"

# Public Access
ADVERTISED_API_URL="https://omni.spaceships.work"
ADVERTISED_K8S_PROXY_URL="https://omni.spaceships.work:8100/"

# Auth0 Config (Legacy flag style to prevent double https:// issue)
AUTH='--auth-auth0-enabled=true --auth-auth0-domain=dev-so2wa1cutbtcbdi8.us.auth0.com --auth-auth0-client-id=[CLIENT_ID]'

# Tailscale Sidecar Key
TS_AUTHKEY=[ts-key-...]
```

#### Deployment (docker-compose.yml)

```yaml
services:
  omni-tailscale:
    image: tailscale/tailscale:latest
    container_name: omni-tailscale
    hostname: omni
    healthcheck:
      test: ["CMD", "tailscale", "status"]
      interval: 10s
      timeout: 5s
      retries: 5
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_EXTRA_ARGS=--advertise-tags=tag:omni
    volumes:
      - ./tailscale-state:/var/lib/tailscale
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    restart: always
    # Bridged Ports for LAN Access (Split DNS support)
    ports:
      - "192.168.10.20:8090:8090"
      - "192.168.10.20:50180:50180/udp"
      - "192.168.10.20:443:443"
      - "192.168.10.20:8100:8100"

  omni:
    image: ghcr.io/siderolabs/omni:${OMNI_IMG_TAG}
    container_name: omni
    network_mode: "service:omni-tailscale"
    depends_on:
      omni-tailscale:
        condition: service_healthy
    restart: always
    volumes:
      - ${ETCD_VOLUME_PATH}:/_out/etcd
      - ${ETCD_ENCRYPTION_KEY}:/omni.asc:ro
      - ${TLS_CERT}:/tls.crt:ro
      - ${TLS_KEY}:/tls.key:ro
    # Explicit device mapping required for SideroLink creation
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
    command: >
      --sqlite-storage-path=${OMNI_SQLITE_PATH}
      --account-id=${OMNI_ACCOUNT_UUID}
      --name=${NAME}
      --cert=/tls.crt
      --key=/tls.key
      --machine-api-cert=/tls.crt
      --machine-api-key=/tls.key
      --private-key-source='file:///omni.asc'
      --event-sink-port=${EVENT_SINK_PORT}
      --bind-addr=${BIND_ADDR}
      --machine-api-bind-addr=${MACHINE_API_BIND_ADDR}
      --k8s-proxy-bind-addr=${K8S_PROXY_BIND_ADDR}
      --advertised-api-url=${ADVERTISED_API_URL}
      --advertised-kubernetes-proxy-url=${ADVERTISED_K8S_PROXY_URL}
      --machine-api-advertised-url=${SIDEROLINK_ADVERTISED_API_URL}
      --siderolink-wireguard-advertised-addr=${SIDEROLINK_WIREGUARD_ADVERTISED_ADDR}
      --initial-users=${INITIAL_USER_EMAILS}
      ${AUTH}
```

### 3.2 Phase 2: The Worker (Cluster B)

#### LXC Host Setup (Proxmox)

1. Create Unprivileged LXC (Ubuntu 24.04)
2. Enable Nesting and TUN device access in `/etc/pve/lxc/ID.conf`:

```text
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

3. **DNS Fix:** Create `/etc/.pve-ignore.resolv.conf` inside the LXC and manually set `/etc/resolv.conf` to `8.8.8.8`

#### Deployment (docker-compose.yml)

> Note: Uses Sidecar pattern to bypass LXC networking limitations.

```yaml
services:
  worker-tailscale:
    image: tailscale/tailscale:latest
    container_name: worker-tailscale
    hostname: proxmox-worker-matrix
    environment:
      - TS_AUTHKEY=[ts-key-...]
      - TS_STATE_DIR=/var/lib/tailscale
      # Force kernel mode to ensure interface creation
      - TS_USERSPACE=false
    volumes:
      - ./tailscale-state:/var/lib/tailscale
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    restart: always
    healthcheck:
      test: ["CMD", "tailscale", "status"]
      interval: 10s
      timeout: 5s
      retries: 3

  omni-infra-provider-proxmox:
    image: ghcr.io/siderolabs/omni-infra-provider-proxmox:latest
    container_name: omni-infra-provider-proxmox
    restart: always
    network_mode: service:worker-tailscale
    depends_on:
      worker-tailscale:
        condition: service_healthy
    command:
      - --omni-api-endpoint=https://omni.spaceships.work
      - --omni-service-account-key=[SA_KEY]
      - --proxmox-url=https://192.168.3.X:8006/api2/json
      - --proxmox-username=root@pam
      - --proxmox-token=[TOKEN]
      - --proxmox-insecure-skip-tls-verify=true
      - --system-id=matrix-cluster
```

---

## 4. Design Decisions

### Authentication: tsidp → Auth0 Pivot

**Initial Approach:** Self-hosted Tailscale Identity Provider (TSIDP)
**Why we tried it:** To keep the entire stack internal and dependent only on the Tailnet
**Problem:** Created a circular dependency. The Omni Hub needed to verify identity against TSIDP, but TSIDP traffic routing and "Machine Boot" authentication for fresh Talos nodes became excessively complex to bootstrap
**Decision:** Switch to Auth0 (SaaS)
**Outcome:** Simplified the OIDC flow. Omni creates a standard outbound connection to Auth0 for verification, removing the local networking bottleneck

---

## 5. Resolved Issues

### DNS Issues

#### Issue 1: The "Split-Brain" Routing Failure

**Symptom:** Talos VMs created by the worker failed to register (SideroLink ✗ red status)
**Investigation:** VMs were resolving omni.spaceships.work to the Tailscale IP, which is unreachable from a fresh, unauthenticated VM
**Resolution:** Implemented Split DNS (Unifi points URL to LAN IP)
**Impact:** VMs could physically reach the server

#### Issue 2: The Proxmox Override

**Symptom:** Even after configuring Unifi, VMs still failed to connect
**Investigation:** Proxmox Hosts were hardcoded to use 1.1.1.1/8.8.8.8. The VMs inherited this, bypassing the Unifi Split DNS
**Resolution:** Changed Proxmox Node System DNS to point to the Unifi Gateway

#### Issue 3: The "Hairpin" Connection Refused

**Symptom:** Admin Mac (on LAN) got ERR_CONNECTION_REFUSED when accessing the Web UI, while external devices worked
**Investigation:** Mac resolved the URL to the LAN IP (via Unifi), but the Docker Container was only listening on the Tailscale interface inside the sidecar
**Resolution:** Added explicit port mapping `192.168.10.20:443:443` to the Docker Compose file

### Non-DNS Issues

#### Issue: Certificate Mismatch

**Subsystem:** Omni / Talos
**Symptom:** VM booted but log showed `x509: certificate is valid for omni.spaceships.work, not omni-internal...`
**Root Cause:** The Omni Hub generated a self-signed cert on the first boot that only included the public name. Changing env vars *after* the fact did not regenerate the cert.
**Resolution:**

1. Aligned DNS so both public and private routes use the same public hostname
2. Deleted the Omni data directory (`/etc/etcd/*`)
3. Restarted Omni to force certificate regeneration with the correct SANs

#### Issue: The Zombie VM

**Subsystem:** Omni / Proxmox
**Symptom:** Infinite reconciliation loop in Omni logs (`resource Links... doesn't exist`)
**Root Cause:** We wiped the Omni database, but the physical VM created by the previous instance was still running. The Provider kept reporting a VM that the new Omni Brain didn't recognize.
**Resolution:** Manually destroyed the VM in Proxmox and deleted the Cluster object in Omni UI

#### Issue: Unprivileged LXC Networking

**Subsystem:** Worker / Tailscale
**Symptom:** Worker container reported `i/o timeout` connecting to Omni. `curl` failed inside LXC but `tailscale ping` worked.
**Root Cause:** Unprivileged LXC permissions prevented Tailscale from creating the `tailscale0` interface, forcing it into Userspace mode which Docker couldn't use.
**Resolution:**

1. Used Docker Sidecar pattern
2. Set `TS_USERSPACE=false` env var
3. Passed `/dev/net/tun` via `devices` mapping

#### Issue: Auth0 Double Protocol

**Subsystem:** Omni / Auth0
**Symptom:** `invalid jwt` error on login
**Root Cause:** Using the `--auth-auth0-domain` flag automatically prepends `https://`. We manually added `https://` in the `.env` file, resulting in `https://https://...`
**Resolution:** Removed protocol from `.env` variable: `dev-so2wa1cut...`

---

## 6. Open Issues / Known Limitations

### Issue: Manual ISO Upload (Without Provider)

**Context:** If NOT using the Proxmox Infrastructure Provider, you must manually provision Talos VMs.

**Workaround:**

1. Download ISO from Omni UI (**Infrastructure > Boot Media**)
2. Upload to Proxmox storage
3. Create VM with ISO attached
4. Convert to Template
5. Configure Machine Class to clone from Template ID

> **Note:** This workflow is unnecessary when using the Proxmox Provider—it handles VM creation automatically.

---

## 7. Key Commands Reference

### Omni Hub (The Brain)

Diagnose startup crashes, authentication errors, and port binding issues.

| Command | Context | What it tells you |
|---------|---------|-------------------|
| `docker logs -f omni` | Startup | Reveals config errors ("missing required config value: SQLite"), auth errors ("invalid jwt"), or success ("reconcile succeeded") |
| `docker logs omni --tail=50` | Auth Debugging | Shows `x509: certificate is valid for...` errors confirming TLS mismatch |
| `docker compose ps` | Connection Refused | Verifies which ports are exposed to LAN |
| `ls -F /etc/etcd/` | Data Persistence | Check for existing database files (`omni.db`) that may need wiping |

### LXC Worker Networking (The Bridge)

Diagnose "Split-Brain" routing issues where the Worker can't reach the Hub.

| Command | Context | What it tells you |
|---------|---------|-------------------|
| `curl -I https://omni.spaceships.work` | Connectivity | Fails with `(7) Failed to connect` if no route to Tailscale IP |
| `host omni.spaceships.work` | DNS | Returns IP—proves DNS works, isolates issue to routing |
| `tailscale ping omni` | Tunnel | Success proves Tailscale binary can talk to Hub (issue is kernel support) |
| `ping -c 2 100.x.y.z` | Kernel Route | `Operation not permitted` confirms unprivileged LXC can't route to tunnel |
| `ip addr show tailscale0` | Interface | Missing interface confirms need for Docker Sidecar pattern |
| `cat /etc/resolv.conf` | DNS Stomping | Shows if MagicDNS (`100.100.100.100`) is overwriting local settings |

### Tailscale Sidecar (The Tunnel)

Verify Docker-in-Docker networking stack.

| Command | Context | What it tells you |
|---------|---------|-------------------|
| `docker logs worker-tailscale` | Mode Check | "configuring userspace WireGuard config" = need `TS_USERSPACE=false` |
| `docker exec worker-tailscale ping <IP>` | Connectivity | Proves sidecar can reach Hub even when LXC host can't |
| `tailscale status` | Healthcheck | Used in docker-compose to gate app container startup |

### Client / External Access

Debug "Hairpin NAT" issues on local network.

| Command | Context | What it tells you |
|---------|---------|-------------------|
| `ping omni.spaceships.work` | Mac Routing | Returns `192.168.10.20` (LAN IP) confirms Unifi Split-DNS working |
| `nslookup omni.spaceships.work` | Resolver | Confirms client is using local DNS, bypassing MagicDNS |

### Nuclear Options (Reset Commands)

Force a clean slate when configuration drifts.

| Command | Purpose |
|---------|---------|
| `docker volume rm <volume_name>` | Delete persistent data to force cert/identity regeneration |
| `sudo rm -rf ./etcd-data/*` | Manual deletion of bind-mounted data |
| `docker compose up -d --force-recreate` | Discard containers, rebuild from fresh config |

---

## 8. Troubleshooting Quick Reference

| Symptom | Likely Cause | Diagnostic | Fix |
|---------|--------------|------------|-----|
| VM boots but "SideroLink ✗" | VM resolving to Tailscale IP (100.x) instead of LAN | Proxmox Shell: `host omni.spaceships.work` | Set Proxmox Node DNS to Unifi Gateway IP |
| Worker `i/o timeout` | Sidecar tunnel down or Userspace mode active | `docker logs worker-tailscale` | Check `TS_USERSPACE=false` and device mapping |
| `invalid jwt` | Auth0 URL misconfiguration | `docker logs omni` | Check `omni.env` for double `https://` |
| `Links... doesn't exist` | Database wiped but VM still running | Proxmox UI check | Delete VM in Proxmox, Delete Cluster in Omni |
| `x509: certificate is valid for...` | Cert generated before DNS alignment | Check cert SANs | Delete `/etc/etcd/*`, restart Omni |
| ERR_CONNECTION_REFUSED (LAN only) | Ports not mapped to LAN IP | Check docker-compose ports | Add explicit IP binding `192.168.10.20:443:443` |

---

## Related Documentation

- [OPERATIONS.md](./OPERATIONS.md) — CLI tools, machine classes, cluster management
