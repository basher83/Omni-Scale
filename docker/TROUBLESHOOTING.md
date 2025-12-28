# Troubleshooting

## VM Network Configuration

### DNS Resolution Failure Prevents Package Installation

**Symptom:** `apt update` fails with "Temporary failure resolving 'archive.ubuntu.com'" and packages cannot be installed.

**Cause:** The VM's netplan configuration had DNS nameservers set to `127.0.0.53` (systemd-resolved stub) with no upstream DNS servers configured.

**Solution:** Edit `/etc/netplan/50-cloud-init.yaml` and add actual DNS servers:
```yaml
nameservers:
  addresses:
  - 192.168.10.1
  - 1.1.1.1
```
Then apply with `sudo netplan apply`.

---

## SSH Connectivity

### Host Key Verification Failed After VM Recreation

**Symptom:** `Host key for X has changed and you have requested strict checking. Host key verification failed.`

**Cause:** The VM was recreated/reinstalled, generating new SSH host keys, but the old keys remained in `~/.ssh/known_hosts`.

**Solution:** Remove the old host key entry:
```bash
ssh-keygen -R <ip-address>
```

---

### SSH Permission Denied (publickey)

**Symptom:** `Permission denied (publickey)` when attempting to SSH to a newly created VM.

**Cause:** SSH public key was not present in the target user's `~/.ssh/authorized_keys` on the VM.

**Solution:** Add your SSH public key to the VM. If password auth is disabled, access the VM console and run:
```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... your-key" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## tsidp Container Issues

### tsidp Times Out on Port 443 (Host Has Native Tailscale)

**Symptom:** Navigating to `https://idp.tailfb3ea.ts.net` times out after showing an untrusted cert warning. The container starts successfully but HTTPS connections fail.

**Cause:** Conflict between the host's native `tailscaled` service and the container's embedded tsnet. Both attempt to manage routing tables, but tsnet in userspace mode inside Docker cannot properly receive traffic routed to its Tailscale IP. Evidence: host cannot ping container's Tailscale IP (100% packet loss), container listens on random high port instead of 443.

**Solution:** Run tsidp on a separate machine without native Tailscale installed, OR use Funnel mode (`TSIDP_USE_FUNNEL=1`) to expose endpoints publicly.

---

### tsidp Permission Denied on State Directory

**Symptom:** `ERROR failed to start tsnet server error="tsnet.Up: tsnet: logpolicy.Config.Save for /var/lib/tsidp/tailscaled.log.conf: open /var/lib/tsidp/tailscaled.log.conf.tmp...: permission denied"`

**Cause:** Docker volume created with root ownership, but tsidp container runs as user `app` (UID 1001).

**Solution:** Fix volume ownership:
```bash
sudo chown -R 1001:1001 /var/lib/docker/volumes/<volume-name>/_data
```

---

### tsidp Hostname Gets Suffixed (idp-1, idp-2, etc.)

**Symptom:** Each time the container is recreated, it registers as `idp-1`, `idp-2`, etc. instead of `idp`.

**Cause:** The previous Tailscale device still exists in the admin console when a new container registers. Tailscale auto-increments the hostname to avoid conflicts.

**Solution:**
1. Remove old device(s) from Tailscale admin console BEFORE starting new container
2. Delete the Tailscale state volume to force fresh registration:
```bash
docker volume rm <ts-state-volume>
```
3. Going forward, use `docker compose down` (without `-v`) to preserve Tailscale state

---

## Omni Container Issues

### Omni Cannot Resolve tsidp Hostname

**Symptom:** `Error: failed to run server: Get "https://tsidp.tailfb3ea.ts.net/.well-known/openid-configuration": dial tcp: lookup tsidp.tailfb3ea.ts.net on 127.0.0.11:53: no such host`

**Cause:** Omni container uses Docker's internal DNS (127.0.0.11) which doesn't know about Tailscale MagicDNS names.

**Solution:** Configure the Tailscale sidecar container with kernel mode networking so it manages DNS:
```yaml
omni-tailscale:
  environment:
    - TS_ACCEPT_DNS=true
    - TS_USERSPACE=false
  cap_add:
    - NET_ADMIN
    - SYS_MODULE
  devices:
    - /dev/net/tun:/dev/net/tun

omni:
  network_mode: service:omni-tailscale
  depends_on:
    - omni-tailscale
```

This makes the tailscale container create a real `tailscale0` interface and manage `/etc/resolv.conf` to use MagicDNS (100.100.100.100).

---

### Omni Fails to Reach tsidp via Tailscale IP

**Symptom:** `tailscale ping` works but ICMP ping and HTTPS connections to tsidp's Tailscale IP fail from the omni-tailscale container.

**Cause:** Tailscale container running in userspace mode (`TS_USERSPACE=true` or missing tun device). No `tailscale0` interface is created, so regular network traffic doesn't route through Tailscale.

**Solution:** Enable kernel mode by adding to docker-compose:
```yaml
environment:
  - TS_USERSPACE=false
cap_add:
  - NET_ADMIN
  - SYS_MODULE
devices:
  - /dev/net/tun:/dev/net/tun
```

Verify with: `docker exec <container> ip addr show | grep tailscale0`

---

### Omni Missing SQLite Storage Path

**Symptom:** `Error: missing required config value: Params.Storage.SQLite.Path, can be specified using --sqlite-storage-path flag`

**Cause:** Omni requires SQLite database path to be explicitly configured.

**Solution:** Add `--sqlite-storage-path=/_out/omni.db` to the omni command in docker-compose.

---

### Omni Cannot Create TUN Device

**Symptom:** `Error: failed to run server: error initializing wgDevice: error creating tun device: CreateTUN("siderolink") failed; /dev/net/tun does not exist`

**Cause:** Omni needs access to `/dev/net/tun` for its WireGuard-based siderolink functionality.

**Solution:** Add tun device and NET_ADMIN capability to omni container:
```yaml
omni:
  cap_add:
    - NET_ADMIN
  volumes:
    - /dev/net/tun:/dev/net/tun
```

---

### Omni Starts Before Tailscale DNS is Ready

**Symptom:** Omni fails with DNS resolution error on first startup, but works after manual restart.

**Cause:** Omni container starts and tries to reach tsidp before the tailscale sidecar has fully initialized and configured MagicDNS. The default `depends_on` only waits for the container to start, not for Tailscale to be connected.

**Solution:** Enable the Tailscale health endpoint and use `condition: service_healthy`:

```yaml
omni-tailscale:
  environment:
    - TS_ENABLE_HEALTH_CHECK=true
  healthcheck:
    test: ["CMD", "wget", "-q", "--spider", "http://localhost:9002/healthz"]
    interval: 5s
    timeout: 3s
    retries: 10
    start_period: 10s

omni:
  depends_on:
    omni-tailscale:
      condition: service_healthy
```

The `/healthz` endpoint returns 200 when Tailscale has a tailnet IP, ensuring the connection is established and MagicDNS is configured before omni starts.

---

## OIDC Authentication Issues

### Invalid JWT - Email Not Verified

**Symptom:** `Failed to confirm public key: invalid jwt` with logs showing `email not verified: user@example.com`

**Cause:** tsidp does not set `email_verified: true` in JWT claims by default. Omni requires verified email addresses.

**Solution:** Add a grant to Tailscale ACLs at https://login.tailscale.com/admin/acls/file:
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

Then restart tsidp to pick up the ACL changes.

---

### Identity Not Authorized for This Instance

**Symptom:** `Failed to confirm public key. The identity user@example.com is not authorized for this instance`

**Cause:** Omni has existing user/identity data from previous runs that conflicts with the `--initial-users` setting.

**Solution:** Clear the omni data volume to reset identity configuration:
```bash
docker compose down
docker volume rm omni_omni-data
docker compose up -d
```

Note: This will delete all cluster configurations. Only use during initial setup.

---

## Docker Volume Management

### Tailscale Hostname Collision After Volume Deletion

**Symptom:** After running `docker compose down -v`, the Tailscale container registers with a suffixed hostname (e.g., `omni-1` instead of `omni`).

**Cause:** The `-v` flag deletes all volumes including Tailscale state. When the container starts fresh, the old device still exists in Tailscale's admin console.

**Solution:**
- **Prevention:** Never use `docker compose down -v` unless you intend to fully reset
- **Recovery:** Remove stale devices from Tailscale admin console, then delete only the `ts-state` volume:
```bash
docker compose down
docker volume rm omni_ts-state
# Remove old device from admin console
docker compose up -d
```

---

## Tailscale DNS Race Condition

### Healthcheck Passes But DNS Not Ready

**Symptom:**
```
Error: failed to run server: Get "https://tsidp.tailfb3ea.ts.net/.well-known/openid-configuration": dial tcp: lookup tsidp.tailfb3ea.ts.net on 100.100.100.100:53: no such host
```

Omni container starts before Tailscale MagicDNS is fully configured, despite healthcheck passing.

**Cause:**
The `/healthz` endpoint returns 200 when Tailscale has an IP address, but DNS resolution isn't configured until slightly after.

**Solution:**
Updated healthcheck to verify both daemon health AND DNS resolution:

```yaml
healthcheck:
  test:
    - CMD-SHELL
    - "wget -q --spider http://localhost:9002/healthz && getent hosts controlplane.tailscale.com"
  interval: 5s
  timeout: 5s
  retries: 20
  start_period: 15s
```

**Rationale:**
- `getent hosts` uses system resolver (respects `/etc/resolv.conf`)
- `controlplane.tailscale.com` is always resolvable via MagicDNS
- No hardcoded tailnet names
- Proves DNS actually works, not just configured

---

## Tailscale Hostname Resolution

### OIDC Provider Not Resolvable on Tailnet

**Symptom:**
```
lookup tsidp.tailfb3ea.ts.net on 100.100.100.100:53: no such host
```

**Cause:**
tsidp container was configured with incorrect Tailscale hostname (`idp` instead of `tsidp`).

**Solution:**
Corrected `TS_HOSTNAME` environment variable in tsidp container to match expected DNS name. Verified resolution:
```bash
docker exec omni-omni-tailscale-1 getent hosts tsidp.tailfb3ea.ts.net
# 100.72.112.31     tsidp.tailfb3ea.ts.net
```

---

## TLS Handshake Issues

### TLS Handshake Timeout on Cold Start

**Symptom:**
```
Error: failed to run server: Get "https://tsidp.tailfb3ea.ts.net/.well-known/openid-configuration": net/http: TLS handshake timeout
```

**Cause:**
Timing issue during initial startup - Omni attempts to connect to OIDC provider before Tailscale certificates are fully ready.

**Solution:**
Restart omni container after tailscale is warm:
```bash
docker compose restart omni
```

**Note:** This is typically only an issue on first startup. Subsequent restarts work cleanly.

---

## Proxmox Infrastructure Provider

### Missing Service Account Key

**Symptom:**
```
WARN[0000] The "OMNI_INFRA_PROVIDER_KEY" variable is not set. Defaulting to a blank string.
Error: rpc error: code = Unauthenticated desc = invalid signature
```

Provider container crash-loops with authentication failures.

**Cause:**
`OMNI_INFRA_PROVIDER_KEY` environment variable not set in `.env` file.

**Solution:**
1. Create service account in Omni UI: Settings → Service Accounts
2. Assign infrastructure provider permissions
3. Generate and copy service account key
4. Add to `.env`:
   ```bash
   OMNI_INFRA_PROVIDER_KEY=<your-service-account-key>
   ```
5. Restart: `docker compose up -d proxmox-provider`

---

### Resource ID Mismatch

**Symptom:**
```
Error: rpc error: code = InvalidArgument desc = resource ID must match the infra provider ID "Proxmox"
```

Provider starts but immediately crashes with InvalidArgument error.

**Cause:**
Provider defaults to lowercase `id="proxmox"`, but Omni expects `id="Proxmox"` (capital P).

**Solution:**
Add explicit `--id` flag to provider command in `compose.yaml`:

```yaml
proxmox-provider:
  command:
    - --config-file=/config.yaml
    - --omni-api-endpoint=https://${OMNI_DOMAIN}/
    - --omni-service-account-key=${OMNI_INFRA_PROVIDER_KEY}
    - --id=Proxmox  # ← Add this
```

**Discovery:**
```bash
docker run --rm ghcr.io/siderolabs/omni-infra-provider-proxmox:latest --help | grep -i id
# --id string    the id of the infra provider (default "proxmox")
```

---

## Container Network Namespace Issues

### Cannot Restart Container - Network Namespace Missing

**Symptom:**
```
Error response from daemon: Cannot restart container: joining network namespace of container: No such container: e84f07b603dd...
```

**Cause:**
When using `network_mode: service:omni-tailscale`, restarting individual containers can break network namespace references.

**Solution:**
Full stack restart required:
```bash
docker compose down
docker compose up -d
```

**Best Practice:**
When containers share network namespaces, always restart the entire stack rather than individual containers.

---

## Omni Not Listening Despite "Up" Status

### Container Running But Not Binding Ports

**Symptom:**
- `docker compose ps` shows omni as "Up"
- Port 8080 not listening: `wget -qO- http://127.0.0.1:8080` → Connection refused
- Provider gets 502 Bad Gateway

**Cause:**
Network namespace corruption after individual container restart attempts.

**Solution:**
Clean restart of entire stack:
```bash
docker compose down
docker compose up -d
```

**Verification:**
```bash
docker exec omni-omni-tailscale-1 ss -tlnp | grep -E '8080|8090|8100'
# Should show omni listening on all three ports
```
