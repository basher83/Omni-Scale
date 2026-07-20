---
name: omni-upgrade
description: >
  Upgrade the self-hosted Omni Hub (Docker Compose stack on omni-host) to a new
  release, including release-note gating, deploy, and post-upgrade verification.
when_to_use: >
  Use when upgrading the Omni backend version, when a renovate PR bumps
  ghcr.io/siderolabs/omni in omni/compose.yml, or when a Talos/Kubernetes bump
  is blocked because the backend does not support the target version.
---

# Omni Hub Upgrade

The Hub version gates which Talos and Kubernetes versions Omni accepts.
This skill upgrades the Hub itself. The human approves the plan; the agent
executes and verifies.

## Facts

- Desired state: the image tag pinned in `omni/compose.yml` (renovate opens a
  PR per Omni release, with release notes attached).
- Deployed state: `omni-host` (a VM — not Holly, which is the Proxmox host
  underneath), directory `/home/ansible/docker/omni`, deployed filename
  `compose.yaml`. It is **not** a git clone — the file must be synced to it.
- Access: `ssh root@omni-host`. `omnictl` runs from the workstation (mise pin).

## Preconditions

1. Read the "Urgent Upgrade Notes" for **every minor version being skipped**:

   ```bash
   gh api repos/siderolabs/omni/releases/tags/vX.Y.0 --jq .body | head -60
   ```

   Specifically check for removed CLI flags against the `command:` block in
   `omni/compose.yml` — a removed flag means a crash loop on boot.
2. Upgrading from older than v1.4.0 requires stepping through v1.4.x first
   (storage migrations). From v1.4.x onward, direct upgrades are supported.
3. State migrations are not guaranteed reversible. Treat rollback as
   unavailable; the plan is roll-forward. Present this in the plan for
   approval on multi-minor jumps.

## Procedure

1. Land desired state first: merge the renovate PR (or edit the pin in
   `omni/compose.yml`), commit, push.
2. Sync the compose file to the host:

   ```bash
   scp omni/compose.yml root@omni-host:/home/ansible/docker/omni/compose.yaml
   ```

3. Apply on the host. `--env-file` is mandatory (compose interpolates
   `${TS_AUTHKEY}` and volume paths at parse time; the env file is not named
   `.env`). **Never use `down -v`** — it deletes Tailscale state and causes
   hostname collisions.

   ```bash
   ssh root@omni-host 'cd /home/ansible/docker/omni && \
     docker compose --env-file omni.env pull && \
     docker compose --env-file omni.env up -d --force-recreate'
   ```

## Verify

All four, in order:

```bash
omnictl get sysversion -o jsonpath='{.spec.backendversion}'   # target version
omnictl get talosversions -o jsonpath='{.metadata.id}' | tail  # new versions appeared
omnictl get infraproviderstatus                                # provider re-registered
omnictl get machines                                           # all CONNECTED true
```

## Post-upgrade sync

Version facts live in multiple places; stale copies cause the next stall.
Update in the same session: the `omnictl` pin in `mise.toml` (client should
match backend), `omni/omni.env.example` if anything changed, and any doc
that names the old version.

## Failure handling

- Container crash-looping: `ssh root@omni-host 'docker logs omni --tail 50'`.
  An unknown-flag error means a removed flag was missed in preconditions —
  fix the `command:` block in the repo, re-sync, re-apply.
- UI/API unreachable but container healthy: check the tailscale sidecar
  (`docker logs omni-tailscale`); the omni container shares its network
  namespace.
- Provider not re-registering after upgrade: check the provider LXC
  (`omni-provider`), see the omni-talos skill for provider lifecycle.
