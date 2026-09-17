---
name: omni-upgrade
description: >
  Upgrade or recover the self-hosted Omni Hub Docker Compose stack on omni-host,
  including release compatibility, persistent Tailscale identity, protected
  state, and service verification. Use for Omni image updates, sidecar recovery,
  or a backend version blocking a Talos/Kubernetes upgrade.
---

# Omni Hub Upgrade

The Hub version gates which Talos and Kubernetes versions Omni accepts.
Use the authorized scope: distinguish service recovery, image download, version
upgrade, and fresh tailnet enrollment. Existing approval remains valid; ask only
when a necessary next action exceeds it. Do not infer cluster upgrades from a Hub
upgrade request.

## Facts

- Desired state: Omni's version pin and Tailscale's floating `stable` tag in
  `omni/compose.yml`. Record resolved image IDs/digests before and after changes.
- Deployed state: `omni-host` (a VM — not Holly, which is the Proxmox host
  underneath), directory `/home/ansible/docker/omni`, deployed filename
  `compose.yaml`. It is **not** a git clone — the file must be synced to it.
- Access: `ssh root@omni-host`. `omnictl` runs from the workstation (mise pin).
- Authentication: deployed Omni uses Auth0; its Tailscale sidecar provides
  network access, not Omni user authentication. Refresh this fact from filtered
  deployed configuration if authentication is in scope; never print environment
  files or unrestricted container inspection output.

## Preconditions

1. Read the "Urgent Upgrade Notes" for **every minor version being skipped**:

   ```bash
   gh api repos/siderolabs/omni/releases/tags/vX.Y.0 --jq .body
   ```

   Specifically check for removed CLI flags against the `command:` block in
   both deployed and checked-in commands. Include target patch notes. Match the
   client to the target backend; Omni 1.11 changes the API version and requires
   upgrading `omnictl` with the backend.
2. Upgrading from older than v1.4.0 requires stepping through v1.4.x first
   (storage migrations). From v1.4.x onward, direct upgrades are supported.
3. State migrations are not guaranteed reversible. Treat rollback as
   unavailable; the plan is roll-forward. Present this in the plan for
   approval on multi-minor jumps.
4. Refresh container IDs, image IDs, mounts, network attachment, and current
   health. Compare rendered deployed Compose with the repository in memory,
   emitting only relevant non-secret differences. Do not overwrite deployment
   differences blindly. Check for concurrent work.
5. Preserve configuration and state in a restricted host-local recovery copy.
   Stop the sidecar for a consistent Tailscale state archive; verify its contents
   against the bind source. Back up Omni's actual storage backend using a
   consistent method (SQLite backup API for a running SQLite database), and check
   integrity. Preserve required encryption material securely when planning full
   recovery. A local copy alone is not a tested disaster-recovery procedure.

## Tailscale identity

Keep `TS_STATE_DIR=/var/lib/tailscale` bound to persistent storage and set
`TS_AUTH_ONCE=true`. An auth key bootstraps enrollment; its expiry does not expire
an already authorized device. A tagged device normally has node-key expiry
disabled, but verify that setting after enrollment.

If login fails, inspect state metadata and structural presence without exposing
private keys. Compare the saved node ID with tailnet inventory. Saved state does
not prove that the device remains registered. `TS_AUTH_ONCE` cannot recover a
deleted registration: if fresh enrollment is outside the approved scope, stop
before replacing credentials or identity. Never delete state to resolve login.
See [Docker parameters](https://tailscale.com/docs/features/containers/docker/docker-params)
and [auth keys](https://tailscale.com/docs/features/access-control/auth-keys).

## Procedure

1. Prepare the reviewed repository/deployment delta. Commit, push, or merge only
   within the user's publication scope. Transfer the intended delta after
   reconciling differences; the deployed file is named `compose.yaml`.
2. Apply on the host. `--env-file` is mandatory (compose interpolates
   `${TS_AUTHKEY}` and volume paths at parse time; the env file is not named
   `.env`). Never use `down -v`, prune state, or remove state bind directories.
   Pull only the approved image references. A pull stages an image; restart does
   not pull or apply changed environment. For recovery without an upgrade,
   verify the local reference resolves to the recorded running image before
   using `--pull never --no-build`.

3. If changing the sidecar or it was stopped for backup, restore it first and verify `Running`, `Online`,
   health, expected device identity/tags, and stable restart count beyond the
   observed failure interval. Use recreation to apply configuration changes;
   a backup-only stop can use `docker start omni-tailscale`. Stop before changing
   Omni if this gate fails. For recreation:

   ```bash
   ssh root@omni-host 'cd /home/ansible/docker/omni && \
     docker compose --env-file omni.env -f compose.yaml up -d \
       --no-deps --force-recreate --pull never --no-build omni-tailscale'
   ```

4. Recreate Omni against the current sidecar after that gate passes, using the
   same command with service `omni`. When the sidecar container ID changes,
   restarting Omni alone leaves its old configured namespace target unchanged.
   Preserve Omni's existing storage mounts and the approved image/command.

## Verify

Verify actual `/proc/<pid>/ns/net` identity for both processes; a configured
`network_mode` reference does not prove a shared live namespace. Check routes,
LAN and tailnet HTTPS with valid TLS, then authenticated management reads:

```bash
omnictl get sysversion -o jsonpath='{.spec.backendversion}'   # target version
omnictl get talosversions -o jsonpath='{.metadata.id}'        # expected version support
omnictl get infraprovidercombinedstatus matrix-cluster -o json # inspect spec.health
omnictl get machines                                           # all CONNECTED true
omnictl get clusterstatus                                      # availability and healthy counts
```

A stored `InfraProviderStatus` only proves registration exists; inspect combined
health for live connectivity. If the CLI key has expired, let the operator finish
its authentication flow, then repeat the reads. Report any pending check or
disconnected resource rather than claiming complete recovery from HTTP 200 alone.

## Post-upgrade sync

Version facts live in multiple places; stale copies cause the next stall.
Update in the same session: the `omnictl` pin in `mise.toml` (client should
match backend), `omni/omni.env.example` if anything changed, and any doc
that names the old version.

## Failure handling

- Container crash-looping: `ssh root@omni-host 'docker logs omni --tail 50'`.
  An unknown-flag error means a removed flag was missed in preconditions —
  fix the `command:` block in the repo, re-sync, re-apply.
- UI/API unreachable: inspect sidecar attachments, interface/routes, and both
  actual namespaces. Daemon restarts can leave Omni in an old namespace. Restore
  only the approved missing attachment; this does not fix authentication or
  automatically reconnect an existing Omni process.
- Filter logs before emitting them: authentication URLs, keys, and unrestricted
  configuration do not belong in the transcript. Record sanitized evidence and
  the resulting deployed state in Lab Operations.
- Provider not re-registering after upgrade: check the provider LXC
  (`omni-provider`), see the omni-talos skill for provider lifecycle.
