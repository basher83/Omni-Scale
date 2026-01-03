# Troubleshooting

Consolidated troubleshooting for Omni-Scale deployment.

---

## Resolved Issues

### DNS / Network Architecture

#### Split-Horizon DNS Resolution Failure (The Four-Day Boss Fight)

**Symptom:** Talos VMs created by provider fail to register. SideroLink shows red X.

**Investigation Path:**
1. VMs boot successfully in Proxmox console
2. Omni shows "Registering" but never progresses
3. VM logs show connection timeouts to `omni.spaceships.work`

**Root Cause:** Five layers of abstraction conspired:
- Docker (Omni) → LXC (Provider) → Proxmox → Talos → Ceph
- `omni.spaceships.work` resolved to Tailscale IP (100.x.y.z) via Cloudflare
- Fresh Talos VMs aren't on Tailscale yet—can't reach that IP
- Proxmox hosts were configured with public DNS (1.1.1.1, 8.8.8.8)
- VMs inherited this DNS, bypassing correctly configured Unifi Split DNS

**Resolution:** Implement Split-Horizon DNS:
1. **Cloudflare (public):** `omni.spaceships.work` → Tailscale IP (for admin access)
2. **Unifi (local):** `omni.spaceships.work` → 192.168.10.20 (LAN IP)
3. **Proxmox hosts:** Change DNS to Unifi Gateway IP so VMs inherit local DNS

**Type:** Architecture fix

**War Story:** Four days of debugging. First Commandment of IT: "It was DNS."

---

#### Docker LAN Port Binding (Hairpin NAT)

**Symptom:** `ERR_CONNECTION_REFUSED` from LAN clients (Mac on same network), but Tailscale access works fine.

**Cause:** Docker containers using Tailscale sidecar only listen on the Tailscale interface (100.x). When Split-Horizon DNS routes LAN clients to the host's physical IP, nothing is listening there.

**Resolution:** Add explicit port mappings with host LAN IP in docker-compose.yml:

```yaml
omni-tailscale:
  ports:
    - "192.168.10.20:443:443"
    - "192.168.10.20:8090:8090"
    - "192.168.10.20:8100:8100"
    - "192.168.10.20:50180:50180/udp"
```

Both paths (Tailscale tunnel and LAN front door) work simultaneously after fix.

**Type:** Fix

---

### Cluster Templates

#### Invalid Cluster Template Format

**Symptom:** `field controlPlane not found in type models.Cluster`

**Cause:** Cluster templates require multi-document YAML, not nested fields.

**Resolution:** Split into separate YAML documents with `---` delimiters:

```yaml
# WRONG - single document
kind: Cluster
name: my-cluster
controlPlane:
  machineClass: control-plane

# CORRECT - multi-document
kind: Cluster
name: my-cluster
kubernetes:
  version: v1.34.2
talos:
  version: v1.12.0
---
kind: ControlPlane
machineClass:
  name: control-plane
  size: 3
```

**Type:** Fix

---

### Machine Classes

#### CEL Storage Selector Type Mismatch

**Symptom:** Storage selector `type == "rbd"` fails with type mismatch error.

**Cause:** `type` is a reserved CEL keyword (built-in function).

**Resolution:** Use only the `name` field:

```yaml
# WRONG
storage_selector: type == "rbd" && name == "vm_ssd"

# CORRECT
storage_selector: name == "local-lvm"
```

**Type:** Workaround

---

#### Storage Name Not Found

**Symptom:** Cluster stuck in `SCALING_UP`, control plane not provisioning.

**Cause:** `storage_selector` referenced non-existent storage.

**Resolution:** Verify names with `pvesh get /storage` on Proxmox, update selector.

**Type:** Fix

---

### Authentication

#### omnictl Authentication Failure

**Symptom:** `rpc error: code = Unauthenticated desc = invalid signature`

**Cause:** omnictl session expired.

**Resolution:** Run any omnictl command (e.g., `omnictl get clusters`) to trigger re-authentication.

**Type:** Fix

---

#### Invalid JWT - Email Not Verified

**Symptom:** `invalid jwt` with `email not verified` in logs.

**Cause:** tsidp doesn't set `email_verified: true` by default.

**Resolution:** Add grant to Tailscale ACLs:

```json
"grants": [{
  "src": ["*"], "dst": ["*"],
  "app": {
    "tailscale.com/cap/tsidp": [{
      "users": ["*"],
      "extraClaims": { "email_verified": true }
    }]
  }
}]
```

**Type:** Fix

---

#### Identity Not Authorized for This Instance

**Symptom:** `identity user@example.com is not authorized for this instance`

**Cause:** Conflicting identity data from previous runs.

**Resolution:** Clear omni data volume (destructive):

```bash
docker compose down
docker volume rm omni_omni-data
docker compose up -d
```

**Type:** Fix

---

### tsidp Service (Historical - Now Using Auth0)

> **Note:** These issues are historical. The deployment has migrated to Auth0 for OIDC authentication. tsidp has been decommissioned. Kept for reference if tsidp is revisited.

#### Systemd Service Syntax Errors

**Symptom:** `Missing '='` errors on lines 12-15 in journal.

**Cause:** Multi-line `ExecStart` with backslashes failed to parse.

**Resolution:** Consolidate to single line:

```ini
ExecStart=/usr/local/bin/tsidp -dir /var/lib/tsidp -hostname idp -port 443
```

Then `systemctl daemon-reload && systemctl restart tsidp`.

**Type:** Fix

---

#### tsidp Not Binding to Port 443

**Symptom:** Service starts but nothing listening on port 443.

**Cause:** tsidp uses tsnet, only listens on Tailscale interface.

**Resolution:** Expected behavior. Access via `https://idp.tailnet.ts.net`.

**Type:** Not a bug

---

#### tsidp Hostname Suffix (idp-1, idp-2)

**Symptom:** Container registers as `idp-1` instead of `idp`.

**Cause:** Previous device still in Tailscale admin console.

**Resolution:**

1. Remove old device from Tailscale admin
2. Delete state volume: `docker volume rm <ts-state-volume>`
3. Use `docker compose down` (no `-v`) to preserve state

**Type:** Fix

---

### Omni Container

#### Cannot Resolve tsidp Hostname

**Symptom:** `lookup tsidp.tailnet.ts.net: no such host`

**Cause:** Docker DNS doesn't know MagicDNS names.

**Resolution:** Configure Tailscale sidecar with kernel mode:

```yaml
omni-tailscale:
  environment:
    - TS_ACCEPT_DNS=true
    - TS_USERSPACE=false
  cap_add: [NET_ADMIN, SYS_MODULE]
  devices: [/dev/net/tun:/dev/net/tun]
omni:
  network_mode: service:omni-tailscale
```

**Type:** Fix

---

#### Missing SQLite Storage Path

**Symptom:** `missing required config value: Params.Storage.SQLite.Path`

**Resolution:** Add `--sqlite-storage-path=/_out/omni.db` to omni command.

**Type:** Fix

---

#### Cannot Create TUN Device

**Symptom:** `/dev/net/tun does not exist`

**Resolution:** Add to omni container:

```yaml
cap_add: [NET_ADMIN]
volumes: [/dev/net/tun:/dev/net/tun]
```

**Type:** Fix

---

#### Omni Starts Before Tailscale Ready

**Symptom:** DNS error on first start, works after restart.

**Cause:** `depends_on` only waits for container start.

**Resolution:** Add healthcheck with DNS verification:

```yaml
omni-tailscale:
  environment: [TS_ENABLE_HEALTH_CHECK=true]
  healthcheck:
    test: ["CMD-SHELL", "wget -q --spider http://localhost:9002/healthz && getent hosts controlplane.tailscale.com"]
    interval: 5s
    timeout: 5s
    retries: 20
omni:
  depends_on:
    omni-tailscale:
      condition: service_healthy
```

**Type:** Fix

---

### Proxmox Provider

#### Missing Service Account Key

**Symptom:** `OMNI_INFRA_PROVIDER_KEY variable is not set`

**Resolution:**

1. Create service account in Omni UI
2. Add to `.env`: `OMNI_INFRA_PROVIDER_KEY=<key>`
3. Restart provider

**Type:** Fix

---

#### Resource ID Mismatch (Proxmox vs proxmox)

**Symptom:** `resource ID must match the infra provider ID "Proxmox"`

**Cause:** Provider defaults to lowercase `proxmox`.

**Resolution:** Add `--id=Proxmox` flag to provider command.

**Type:** Fix

---

### Docker/Network

#### DNS Resolution Failure (apt update fails)

**Symptom:** `Temporary failure resolving 'archive.ubuntu.com'`

**Cause:** DNS set to `127.0.0.53` with no upstream.

**Resolution:** Add real DNS servers to netplan:

```yaml
nameservers:
  addresses: [192.168.10.1, 1.1.1.1]
```

**Type:** Fix

---

#### SSH Host Key Verification Failed

**Symptom:** `Host key has changed` after VM recreation.

**Resolution:** `ssh-keygen -R <ip-address>`

**Type:** Fix

---

#### Container Network Namespace Missing

**Symptom:** `joining network namespace of container: No such container`

**Cause:** Individual restart breaks shared network namespace.

**Resolution:** Full stack restart: `docker compose down && docker compose up -d`

**Type:** Fix

---

#### Tailscale Hostname Collision After -v

**Symptom:** Hostname becomes `omni-1` after `docker compose down -v`.

**Cause:** `-v` deletes Tailscale state; old device persists in admin.

**Resolution:**

- Never use `-v` unless full reset intended
- Remove stale devices from Tailscale admin

**Type:** Fix

---

## Open Issues

*No open issues at this time.*

---

## Closed/Won't Fix Issues

### Machine Classes

#### CEL Storage Type Filtering Not Supported

**Symptom:** Cannot filter by storage type (rbd, lvmthin, zfspool) in CEL selectors.

**Attempts:**
- `type == "rbd"` fails (`type` is reserved CEL keyword)
- Searched Sidero docs - only `name` documented
- Searched provider source - no type field exposed to CEL

**Resolution:** Filter by name only. This is a limitation, not a bug.

```yaml
# Use this
storage_selector: name == "vm_ssd"

# Not this (fails)
storage_selector: type == "rbd"
```

**Status:** Workaround in place. Not pursuing further.

---

## Diagnostic Commands

### Firewall

```bash
sudo iptables -L -n -v
sudo nft list ruleset
sudo systemctl status ufw
```

### Ports

```bash
sudo ss -tlnp
sudo ss -tlnp | grep :443
```

### Service Logs

```bash
sudo journalctl -u tsidp -f
docker compose logs -f omni
docker compose logs -f proxmox-provider
```

### Tailscale

```bash
docker exec <container> tailscale status
docker exec <container> getent hosts tsidp.tailnet.ts.net
docker exec <container> ip addr show | grep tailscale0
```

---

## References

- [Cluster Templates](https://omni.siderolabs.com/reference/cluster-templates)
- [omni-infra-provider-proxmox](https://github.com/siderolabs/omni-infra-provider-proxmox)
