# Troubleshooting

Consolidated troubleshooting for Omni-Scale deployment.

---

## Resolved Issues

### Networking

#### Cilium MTU Auto-Detect Poisoning (The Silent Assassin)

**Symptoms:**
- Web UIs through Tailscale Ingress load slowly or time out (Phoenix, ArgoCD, Homarr)
- `kubectl exec` and `kubectl port-forward` hang or return partial output
- `cilium upgrade` and `cilium status` return `context deadline exceeded`
- Log tails and large responses stall mid-stream
- Throughput through Tailscale Ingress at ~22 KB/s (commit `e0d5f5e`)

**Root Cause:**

Omni-managed Talos nodes carry a `siderolink` WireGuard tunnel at MTU 1280. Verified 2026-04-16 on node 192.168.3.155:

```bash
talosctl -n 192.168.3.155 get links siderolink -o yaml | grep -E "mtu|kind"
#   mtu: 1280
#   kind: wireguard
```

Without `--set MTU=1450` at Cilium install, pod networking ends up at 1280. Setting MTU=1450 in `cilium-config` and restarting affected pods restores throughput.

Parts of the failure chain that are not mapped from primary evidence:

- Cilium's documented auto-detection (PR [cilium/cilium#4687](https://github.com/cilium/cilium/pull/4687)) reads the MTU of the default-route device. Issue [cilium/cilium#14339](https://github.com/cilium/cilium/issues/14339) shows a 9000-MTU interface winning over a 1500-MTU one. The exact path that resolves to siderolink's 1280 on Talos is not documented in upstream sources.
- Pre-fix pod MTU across namespaces was asserted in the 2026-04-06 fix session AAR but not sampled in any record. Post-fix sampling confirms 1450 on both Tailscale proxies and Longhorn manager.
- Tailscale Ingress proxy pods use gVisor userspace netstack ([Tailscale docs](https://tailscale.com/docs/concepts/userspace-networking); local research at `workshop/ensue-snapshot/2026-04-14/research/otel-protocol-tailscale/technical/tailscale-h2c-proxy-mechanism.md`). Tailscale documents a kernel-vs-netstack performance gap ([kb/1177](https://tailscale.com/kb/1177/kernel-vs-userspace-routers/)) but does not document MTU-fragmentation behavior under netstack specifically. Tailscale Ingress was the loudest symptom; the mechanism for that is not proven.

Fix session AAR: `lab-polish/aar/2026-04-06-cilium-mtu-siderolink-fix.md`.

**Diagnostic commands:**

```bash
# ConfigMap — expect "1450"
kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.mtu}'; echo

# Cilium agent reported MTU
kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -1 | \
  xargs -I{} kubectl exec -n kube-system {} -c cilium-agent -- cilium status | grep -i mtu

# Pod-level MTU
kubectl exec -n <namespace> <pod-name> -- ip link show eth0 | grep mtu

# Siderolink interface on a Talos node
talosctl -n <node-ip> get links siderolink -o yaml | grep -E "mtu|kind"

# Rule out DERP-relayed Tailscale path as a separate cause
tailscale ping <peer-hostname>
# Expect "via <IP>:<port>", not "via DERP"
```

**Primary Fix (new installs):**

Add `--set MTU=1450` to every Cilium install and upgrade command. 1450 = 1500 NIC minus 50 VXLAN overhead (commit `e0d5f5e`). Present in `docs/guides/CILIUM.md` and in `mothership-gitops/README.md`.

**Fallback Fix (live cluster already broken):**

`cilium upgrade --set MTU=1450` is the documented path. In the 2026-04-06 fix session, that path did not update `cilium-config`.

Cluster and CLI versions (verified 2026-04-16):

```bash
kubectl get ds cilium -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'
# → quay.io/cilium/cilium:v1.18.6@sha256:42ec562a5ff6c8a860c0639f5a7611685e253fd9eb2d2fcdade693724c9166a4

cilium version
# cilium-cli: v0.19.2
# cilium image (default): v1.19.1
```

DaemonSet is v1.18.6; CLI defaults to v1.19.1. The AAR attributes the SSA conflict to that skew. No upstream Cilium issue or PR documents CLI-version skew as a documented cause of SSA conflicts on `cilium-config`.

The AAR reports `--helm-set upgrade.serverSideApply.force=true` was tried and did not resolve the conflict. No transcript of that command is in the record. Trying it before the ConfigMap fallback is reasonable.

The fix session transcript also shows `context deadline exceeded` errors during `cilium upgrade`. The prior agent's note: "likely the Tailscale proxy throughput issue (ironic) slowing down the Helm chart pull." Whether the CLI routed through a Tailscale Ingress proxy at that moment is not recorded. The timeouts are observed; the causal attribution is hypothesis.

**Fallback recipe:**

```bash
kubectl patch configmap cilium-config -n kube-system \
  --type merge -p '{"data":{"mtu":"1450"}}'
kubectl rollout restart daemonset/cilium -n kube-system
kubectl rollout restart daemonset/cilium-envoy -n kube-system

# Tailscale namespace is "tailscale-operator". Pod veth MTU is set at pod
# creation; existing pods keep the old MTU until replaced.
kubectl get statefulset -n tailscale-operator -o name | \
  xargs -I{} kubectl rollout restart {} -n tailscale-operator

kubectl get cm -n kube-system cilium-config -o jsonpath='{.data.mtu}'; echo
kubectl exec -n tailscale-operator <any-ts-pod> -- ip link show eth0 | grep mtu
```

StatefulSet count (verified 2026-04-16):

```bash
kubectl get statefulset -A | grep -c tailscale-operator
# → 11
```

The count drifts as apps are added or removed.

**Durability:**

The ConfigMap patch does not survive a future `cilium install`. The install and upgrade runbooks carry `--set MTU=1450` for durability.

**Related observation:**

`cilium status` reports `Auto-detected cluster name: talos-prod-operator-tailfb3ea-ts-net` — the Tailscale hostname. Harmless today. If ClusterMesh or cluster-name-keyed tooling is added, set `cluster.name` explicitly.

**Type:** Silent performance bug

---

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

### Proxmox Provider Hostname Conflict (Requires Local Patch)

**Symptom:** Talos VMs fail to register or show hostname conflicts during provisioning.

**Error signature in `omnictl machine-logs`:**
```
static hostname is already set in v1alpha1 config
```

**Diagnostic command:**
```bash
# Check machine logs for hostname conflict
omnictl machine-logs <machine-id> --tail 100 | grep -i hostname

# Check provider logs for configureHostname step
docker logs omni-provider-proxmox-provider-1 --tail 100 | grep -i hostname
```

**Root Cause:** The upstream `omni-infra-provider-proxmox` injects a `configureHostname` step that sets `machine.network.hostname` to the Omni request ID. This conflicts with Omni's hostname management.

**Location:** `internal/pkg/provider/provision.go` lines 193-197

**Resolution:** Build a patched provider image with the `configureHostname` step removed:

```go
// REMOVE THIS STEP:
provision.NewStep("configureHostname", func(ctx context.Context, _ *zap.Logger, pctx provision.Context[*resources.Machine]) error {
    return pctx.CreateConfigPatch(ctx, "000-hostname-%s"+pctx.GetRequestID(), []byte(fmt.Sprintf(`machine:
  network:
    hostname: %s`, pctx.GetRequestID())))
}),
```

**Building the patched image (from Apple Silicon):**

```bash
# Clone and patch
git clone https://github.com/siderolabs/omni-infra-provider-proxmox.git
cd omni-infra-provider-proxmox
# Remove configureHostname step from internal/pkg/provider/provision.go

# Cross-compile (kres Makefile is broken for arm64→amd64)
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-s" \
    -o omni-infra-provider-proxmox-linux-amd64 \
    ./cmd/omni-infra-provider-proxmox

# Build minimal container
cat <<'EOF' | docker build --platform linux/amd64 -t ghcr.io/siderolabs/omni-infra-provider-proxmox:local-fix -f - .
FROM ghcr.io/siderolabs/fhs:v1.11.0 AS fhs
FROM ghcr.io/siderolabs/ca-certificates:v1.11.0 AS certs
FROM scratch
COPY --from=fhs / /
COPY --from=certs / /
COPY omni-infra-provider-proxmox-linux-amd64 /omni-infra-provider-proxmox
ENTRYPOINT ["/omni-infra-provider-proxmox"]
EOF

# Transfer to provider host
docker save ghcr.io/siderolabs/omni-infra-provider-proxmox:local-fix | ssh omni-provider 'docker load'
```

**Update compose.yml:**

```yaml
services:
  proxmox-provider:
    image: ghcr.io/siderolabs/omni-infra-provider-proxmox:local-fix
```

**Status:** Local workaround only. Not yet submitted upstream.

**Related:** PR #38 (node pinning) submitted by project author: https://github.com/siderolabs/omni-infra-provider-proxmox/pull/38

**Type:** Upstream bug / Local patch

---

### VM Migration Breaks Talos State

**Symptom:** After Proxmox live migration, Talos node shows "Talos is not installed" or fails to rejoin cluster.

**Error signature:**
```
Talos is not installed
static hostname is already set in v1alpha1 config
```

**Cause:** Talos machine identity is tied to the original provisioning context. Migration preserves disk but breaks the node's relationship with Omni/SideroLink. Migrated VMs have stale state from the previous provisioning.

**Migration blockers you'll hit first:**
```
Cannot migrate with local CD/DVD
```
Fix with: `qm set <VMID> --ide2 none` — but don't bother, migration will break Talos anyway.

**Resolution:** Don't migrate Talos VMs. Accept initial node distribution or destroy and recreate:

```bash
# Destroy cluster (Provider will clean up VMs)
omnictl cluster template delete -f clusters/talos-prod-01.yaml

# Wait for cleanup
sleep 20 && omnictl get machines

# Redeploy
omnictl cluster template sync -f clusters/talos-prod-01.yaml
```

**Note:** CEPH shared storage makes migration technically possible, but Talos state doesn't survive it. This is a fundamental constraint, not a bug.

**Type:** Constraint

---

### Machine Stuck in "Destroying" State with Finalizers

**Symptom:** Machine shows "Destroying/Unreachable" in Omni UI for 24+ hours. Cannot delete via UI or `omnictl delete machine`.

**Error signature:**
```
rpc error: code = PermissionDenied desc = only read access is permitted for resources of type machines.omni.sidero.dev
```

**Cause:** Out-of-band VM deletion in Proxmox (e.g., manual `qm destroy` or Proxmox UI) causes state drift. The VM is gone but Omni still has the machine resource with finalizers preventing cleanup.

**Key insight:** `machine` resources are read-only to users (even Admins). You must delete the `clustermachine` resource instead.

**Resolution:**

```bash
# Find the stuck machine
omnictl get machines -o table

# Delete the clustermachine (NOT the machine)
omnictl delete clustermachine <machine-uuid>

# Verify cleanup
omnictl get machines -o table
```

**Type:** State drift recovery

---

### "Only Read Access Is Permitted" Despite Admin Role

**Symptom:** `omnictl delete machine <uuid>` fails with permission error even for Admin users.

**Error signature:**
```
rpc error: code = PermissionDenied desc = only read access is permitted for resources of type machines.omni.sidero.dev
```

**Cause:** The `machines.omni.sidero.dev` resource type is read-only by design. This isn't a permissions bug—it's intentional. Machines are managed by the infrastructure provider.

**Resolution:** Use `clustermachine` instead:

```bash
# This fails (machines are read-only)
omnictl delete machine <uuid>

# This works
omnictl delete clustermachine <uuid>
```

**Type:** Expected behavior (misleading error message)

---

### NodeRestriction Blocks node-role.kubernetes.io/* Labels

**Symptom:** Talos node stuck in reboot loop after provisioning.

**Error signature in node events or kubelet logs:**
```
nodes X is forbidden: is not allowed to modify labels: node-role.kubernetes.io/worker
```

**Cause:** Kubernetes NodeRestriction admission controller blocks kubelets from setting labels in protected namespaces:
- `node-role.kubernetes.io/*`
- `kubernetes.io/*` (except specific allowed keys like `topology.kubernetes.io/zone`)

If your cluster template sets these labels in `machine.nodeLabels`, the kubelet will fail to apply them on every boot.

**Resolution:** Remove protected labels from cluster template or use an unprivileged namespace:

```yaml
# WRONG - blocked by NodeRestriction
machine:
  nodeLabels:
    node-role.kubernetes.io/worker: ""

# CORRECT - use custom namespace
machine:
  nodeLabels:
    omni.sidero.dev/role: worker

# CORRECT - skip the label entirely, apply externally after node joins
# (leave nodeLabels empty or omit the protected key)
```

**Alternative:** Apply labels externally after the node joins using kubectl:
```bash
kubectl label node <node-name> node-role.kubernetes.io/worker=""
```

**Type:** Kubernetes constraint

---

### Control Plane Node Distribution Cannot Be Pinned

**Symptom:** Control plane VMs all land on same Proxmox node despite having per-node machine classes.

**Error when trying multiple ControlPlane sections:**
```
Error: 1 error occurred:
    * template should contain 1 controlplane, got 3
```

**Cause:** Omni cluster templates require **exactly 1** `kind: ControlPlane` section. Unlike Workers (which can have multiple named sections), you cannot specify multiple ControlPlane sections with different machine classes.

**What works vs. what doesn't:**

| Component | Multiple Sections | Node Pinning | Result |
|-----------|------------------|--------------|--------|
| Workers | ✓ Yes | ✓ Works | Correct distribution |
| ControlPlane | ✗ No (exactly 1) | ✗ N/A | Provider picks one node |

**Workarounds:**

1. **Accept CP distribution** — Let Provider place CPs, pin only workers
2. **Proxmox HA Groups** — Configure at hypervisor level (outside Omni)
3. **Feature request** — Omni should support multiple ControlPlane sections or Provider anti-affinity

**Resolution:** For production cluster, accepted suboptimal distribution:
- Golf: 3 CPs + 1 Worker
- Hotel: 1 Worker
- Foxtrot: 1 Worker (+ provider LXC)

**Related:** PR #38 adds `node:` field support to Provider, but Omni template format prevents using it for CPs.

**Type:** Omni Limitation

---

## GitOps / Application Issues

Application-level troubleshooting lives in `../mothership-gitops/docs/troubleshooting.md`.
That repo owns ArgoCD app waves, Longhorn, ESO, Tailscale Operator manifests,
Tailscale Ingress exposure, monitoring, dashboards, and workload operations.

Keep only substrate implications here. If a GitOps application cannot schedule
because there are too few worker nodes, fix the substrate in this repo by adding
or resizing machine classes and updating `clusters/talos-prod-01.yaml`.

Example: ArgoCD Redis HA requires three schedulable worker slots when it uses
three replicas with pod anti-affinity. If the cluster has three tainted control
planes and only two workers, the third Redis pod remains Pending. Add another
worker MachineClass and sync the cluster template here, then let
`../mothership-gitops` reconcile the application.

```bash
omnictl apply -f machine-classes/matrix-worker-foxtrot.yaml
omnictl cluster template sync -f clusters/talos-prod-01.yaml
```

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
