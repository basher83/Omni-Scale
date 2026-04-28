# Omni-Scale

Self-hosted Sidero Omni deployment kit with Tailscale authentication and Proxmox infrastructure provider.

## Repo Boundary

This repo answers: how is the Omni-managed Talos substrate created and operated?

Omni-Scale owns the self-hosted Omni Hub, the Proxmox infrastructure provider,
cluster templates, machine classes, Talos node requirements, SideroLink/DNS/Tailscale
access constraints, and the handoff into GitOps.

It does not own post-bootstrap platform applications. Longhorn Helm values,
backup schedules, StorageClasses, ArgoCD app waves, ESO app wiring, Tailscale
Operator manifests, monitoring, dashboards, and workload exposure live in
`../mothership-gitops`. This repo may document the substrate requirement that
enables those systems, such as Talos worker mount patches for Longhorn, but
the GitOps repo is the source of truth for their implementation and operation.

## What This Does

Omni-Scale deploys Sidero Omni for managing Talos Linux Kubernetes clusters on Proxmox
infrastructure. The architecture separates the control plane (Omni Hub) from the VM
provisioner (Proxmox Provider), connected via Tailscale.

<!-- markdownlint-disable-next-line MD033 -->
<img src="docs/assets/talos-prod-01.jpeg" alt="Cluster topology" style="max-width:600px; width:100%; height:auto;" />

The Provider sits on the same L2 network as Talos VMs — this is required for SideroLink registration during boot.

## Repository Structure

This is a reference implementation. Each directory has its own README with details.

| Directory | Purpose |
|-----------|---------|
| `omni/` | Omni Hub Docker Compose stack |
| `proxmox-provider/` | Proxmox infrastructure provider |
| `clusters/` | Cluster templates (Omni format) |
| `machine-classes/` | VM sizing definitions |
| `docs/` | Deployment, operations, troubleshooting |
| `specs/` | Infrastructure specifications |

## Documentation

| Document | Purpose |
|----------|---------|
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Full installation runbook |
| [OPERATIONS.md](docs/OPERATIONS.md) | Day-to-day management |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Issue resolution |
| [CILIUM.md](docs/guides/CILIUM.md) | CNI installation post-bootstrap |

## Critical Gotchas

These cost days of debugging. Don't repeat them.

### Cilium MTU Auto-Detect (The Silent Assassin)

Unlike the other gotchas in this list, this one ran for months without anyone
noticing. Tailscale Ingress throughput sat at ~22 KB/s instead of ~99 Mbps
(commit `e0d5f5e`). No errors. No alerts. Just slow web pages.

Omni's `siderolink` WireGuard tunnel runs at MTU 1280 on every Talos node
(`talosctl get links siderolink -o yaml` → `mtu: 1280, kind: wireguard`).
Without `--set MTU=1450` at Cilium install, pod networking ends up at 1280.
The exact Cilium auto-detect path that resolves to 1280 on Talos is not
mapped — see CILIUM.md for what is and isn't documented.

**Fix**: Install and upgrade Cilium with `--set MTU=1450` (1500 NIC minus 50
VXLAN overhead). For a live cluster already affected, patch `cilium-config`
and restart the Cilium DaemonSets plus the `tailscale-operator` namespace
StatefulSets — see [CILIUM.md](docs/guides/CILIUM.md) and
[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The ConfigMap patch does not
survive a future `cilium install`; update the runbooks too.

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

Uses [mise](https://mise.jdx.dev/) for tool management. Run `mise install` then `mise tasks`
to see available commands.

## References

- [Sidero Omni Documentation](https://omni.siderolabs.com/)
- [omni-infra-provider-proxmox](https://github.com/siderolabs/omni-infra-provider-proxmox)
- [PR #38: Node Pinning](https://github.com/siderolabs/omni-infra-provider-proxmox/pull/38) (contributed by this project)
- [Talos Linux](https://www.talos.dev/)
- [sidero-omni-talos-proxmox-starter](https://github.com/mitchross/sidero-omni-talos-proxmox-starter) (reference implementation that inspired this project)

## License

MIT
