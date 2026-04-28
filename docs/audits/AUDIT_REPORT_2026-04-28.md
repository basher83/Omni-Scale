# Documentation Audit Report

<!-- markdownlint-disable MD013 -->

Generated: 2026-04-28 | Commit: e0d5f5e

## Scope

This audit checked user-facing markdown in the repository and skipped `docs/plans/` and prior audit output. The scan covered `README.md`, `CLAUDE.md`, `scripts/README.md`, `machine-classes/README.md`, `clusters/README.md`, `docs/DEPLOYMENT.md`, `docs/OPERATIONS.md`, `docs/TROUBLESHOOTING.md`, `docs/ROADMAP.md`, `docs/guides/CILIUM.md`, `docs/guides/talos-proxmox-research.md`, `docs/components/longhorn-storage.md`, and `docs/references/providerdata-fields.md`.

Verification was local-first. I checked documented paths, compose services, environment variables, script behavior, YAML inventory, and command references against the checked-in repository. I then cross-referenced the sibling GitOps repository at `/Users/basher8383/3I/lab/mothership-gitops` for claims that explicitly reference `mothership-gitops`. Claims about the live cluster and upstream behavior are still not treated as false unless contradicted by local or sibling-repo evidence.

## Executive Summary

| Metric | Count |
|--------|-------|
| Documents scanned | 13 |
| Verifiable claims checked | 123 |
| Verified true | 96 |
| Verified false | 24 |
| Needs live or external review | 9 |

The main documentation drift is structural rather than cosmetic. Several docs still describe a `specs/` and `pending/` workflow that is not present in the repo. Operations and deployment docs also mix older generic filenames and older Proxmox provider compose syntax with the current Matrix-specific files. The current provider compose service is `proxmox-provider` using `ghcr.io/siderolabs/omni-infra-provider-proxmox:local-fix`, `--config-file=/config.yaml`, and `OMNI_SERVICE_ACCOUNT_KEY`; multiple docs still refer to `omni-infra-provider-proxmox`, `:latest`, inline Proxmox flags, or `OMNI_INFRA_PROVIDER_KEY`.

## False Claims Requiring Fixes

### README.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 26 | Repository structure includes `specs/` for infrastructure specifications. | No `specs/` directory exists in the repository. | Remove the row or recreate the `specs/` tree and document its current schema. |

### CLAUDE.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 18 | Specs in `specs/*.yaml` define desired state. | No `specs/` directory or YAML specs exist. | Remove the Specs section or replace it with the current source of desired state, likely `clusters/` and `machine-classes/`. |
| 25 | `@specs/README.md` contains schema documentation. | `specs/README.md` does not exist. | Point to an existing schema/reference file or delete the reference. |

### docs/ROADMAP.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 19 | Optimized machine classes are ready in `pending/`. | No `pending/` directory exists. Current optimized classes appear under `machine-classes/matrix-*.yaml`. | Update the near-term status to point at `machine-classes/` or remove the stale item. |
| 21 | Storage solution decision is still Longhorn vs Proxmox CSI. | `docs/components/longhorn-storage.md` states Longhorn is deployed, default, and backed by worker mount patches in `clusters/talos-prod-01.yaml`. | Mark the storage decision as made, or move any remaining comparison work into a live-review queue. |
| 59 | `specs/omni.yaml` contains the current phase implementation. | `specs/omni.yaml` does not exist. | Replace with `clusters/talos-prod-01.yaml`, a current plan, or remove the execution details section. |

### docs/OPERATIONS.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 5 | Prerequisite runbook is `docs/Sidero_Omni_Runbook.md`. | That file does not exist. The local deployment runbook is `docs/DEPLOYMENT.md`. | Link to `DEPLOYMENT.md`. |
| 107-108 | Apply `machine-classes/control-plane.yaml` and `machine-classes/worker.yaml`. | Those files do not exist. Current files are `matrix-control-plane.yaml`, `matrix-worker-foxtrot.yaml`, `matrix-worker-golf.yaml`, and `matrix-worker-hotel.yaml`. | Replace with the actual Matrix class apply commands. |
| 120 | Example file is `machine-classes/control-plane.yaml`. | That file does not exist and the snippet contains a TODO placeholder. | Use a real excerpt from `machine-classes/matrix-control-plane.yaml`. |
| 135, 200, 208 | Sync `cluster-template.yaml`. | No `cluster-template.yaml` exists. Current production template is `clusters/talos-prod-01.yaml`; test template is `clusters/test/test-cluster.yaml`. | Use a real template path. |
| 143 | Apply `clusters/my-cluster.yaml`. | That file does not exist. | Use `clusters/talos-prod-01.yaml` or mark the command as a placeholder example. |
| 172 | Provider logs use `docker compose logs -f omni-infra-provider-proxmox`. | Current compose service is `proxmox-provider` in `proxmox-provider/compose.yml`. | Change to `docker compose logs -f proxmox-provider` and mention running it from `proxmox-provider/`. |

### clusters/README.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 123, 126, 129, 132, 138 | Commands use `clusters/test-cluster.yaml`. | The checked-in test template is `clusters/test/test-cluster.yaml`. | Update all command examples to the existing path. |
| 216 | Example references `patches/gpu-worker.yaml`. | The repo has `clusters/patches/examples/gpu-worker.yaml`, not `patches/gpu-worker.yaml`. | Update the example path or add the expected patch file. |

### docs/DEPLOYMENT.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 27 | Current `docker-compose.yml` uses `TS_EXTRA_ARGS=--advertise-tags=tag:omni`. | `omni/compose.yml` does not set `TS_EXTRA_ARGS`; `omni/omni.env.example` also has no `TS_EXTRA_ARGS`. | Either add the setting to compose/env examples or remove the claim. |
| 357-359 | Omni Tailscale sidecar environment includes `TS_EXTRA_ARGS`. | Current `omni/compose.yml` only sets `TS_AUTHKEY` and `TS_STATE_DIR`. | Align the compose snippet with `omni/compose.yml`. |
| 457-470 | Provider service is `omni-infra-provider-proxmox`, uses `:latest`, and passes Proxmox URL/credentials as command flags. | Current `proxmox-provider/compose.yml` service is `proxmox-provider`, image tag is `:local-fix`, and it uses `--config-file=/config.yaml` plus env vars for Omni endpoint, service key, and provider id. Proxmox credentials live in `proxmox-provider/config.yaml.example`. | Replace the provider compose block with the checked-in compose and config split. |

### docs/TROUBLESHOOTING.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 380 | Missing SQLite fix is `--sqlite-storage-path=/_out/omni.db`. | Current env default is `OMNI_SQLITE_PATH=/_out/etcd/omni.db`; compose passes `--sqlite-storage-path=${OMNI_SQLITE_PATH}`. | Update the path to `/_out/etcd/omni.db` or refer to `OMNI_SQLITE_PATH`. |
| 394 | TUN fix adds `/dev/net/tun:/dev/net/tun` under `volumes`. | Current compose uses `devices`, not `volumes`, for `/dev/net/tun`. | Change the snippet to `devices: [/dev/net/tun:/dev/net/tun]`. |
| 431-436 | Missing provider key variable is `OMNI_INFRA_PROVIDER_KEY`. | Current provider env example and compose use `OMNI_SERVICE_ACCOUNT_KEY`. | Rename the documented variable. |
| 528 | Provider log command uses container `omni-provider-proxmox-provider-1`. | Current provider compose sets `container_name: proxmox-provider`. | Change to `docker logs proxmox-provider --tail 100` or `docker compose logs proxmox-provider`. |
| 582 | Local workaround status says not yet submitted upstream. | The README says PR #38 was contributed by this project; the local patch status may be stale or conflates node pinning with hostname removal. | Reword narrowly: local hostname workaround remains local unless upstream hostname fix is confirmed. |

### docs/components/longhorn-storage.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 13, 53, 220 | Helm values live at `mothership-gitops/apps/longhorn/values.yaml` / `apps/longhorn/values.yaml`. | The sibling repo has no `apps/longhorn/values.yaml`. Helm values are inline under `valuesObject` in `apps/longhorn/application.yaml`. | Replace the values path with `apps/longhorn/application.yaml` and describe inline Helm values. |
| 74-79 | Redis HA PVCs are `critical`, Homarr is `important`, and Netdata is `standard`. | `mothership-gitops/docs/backup-storage.md` maps Homarr to `critical`, the three ArgoCD Redis HA PVCs to `important`, and Netdata PVCs to `standard`. The sister audit says live Longhorn labels match that mapping. | Update the PVC inventory tiers to the GitOps mapping. |
| 103-107 | Critical backups retain 24, important retains 7, and standard runs daily at 03:00 retaining 3. | `mothership-gitops/apps/longhorn/recurringjobs.yaml` defines critical `0 */4 * * *` retain 42, important `0 2 * * *` retain 14, and standard `0 3 * * 0` retain 4. | Replace the schedule table with the current recurring jobs. |
| 196 | Backup schedule not yet applied; Phase 6.3 pending. | The sibling repo has `apps/longhorn/recurringjobs.yaml`, `apps/longhorn/storageclasses.yaml`, and a completed audit saying live backup-tier labels match documented PVC mapping with recent backups. | Mark backup schedules as implemented, with any remaining work scoped to restore/client verification if applicable. |
| 209 | RecurringJob schedules are not yet applied. | RecurringJobs are checked into `mothership-gitops/apps/longhorn/recurringjobs.yaml` and the sibling audit reports live backup labels/recent backups. | Change status to applied/managed by GitOps, subject to live recheck when needed. |

### scripts/README.md

| Line | Claim | Reality | Fix |
|------|-------|---------|-----|
| 7 | DR script executes the full drill without human intervention after initial confirmation. | The script has a conditional second prompt when `universal-auth-credentials` is missing. | Say it is normally non-interactive after start confirmation, except for the documented secret-bootstrap prompt. |
| 87 | Provider log check uses `docker logs omni-provider-proxmox-provider-1`. | Current provider container is `proxmox-provider` in `proxmox-provider/compose.yml`. | Update the log command or explain that this is a legacy host/container name if still true in deployment. |

## Pattern Summary

| Pattern | Count | Root cause |
|---------|-------|------------|
| Missing desired-state/spec paths | 4 | Docs retain an older `specs/` workflow even though current desired state is in `clusters/` and `machine-classes/`. |
| Generic example paths replacing real Matrix files | 6 | Operations and cluster docs were not updated after Matrix-specific filenames were introduced. |
| Proxmox provider compose drift | 7 | Docs mix old provider service names, image tag, env variable names, and command flags with the current `proxmox-provider/compose.yml`. |
| Stale roadmap/status claims | 3 | Roadmap still describes pre-Longhorn and pre-redeploy state. |
| Longhorn GitOps drift | 5 | `docs/components/longhorn-storage.md` predates the current `mothership-gitops` backup implementation and still references a non-existent values file plus old backup tiers/status. |

## Verified True Highlights

The core Omni compose shape matches several important claims: `omni/compose.yml` defines `omni-tailscale` and `omni`, binds the LAN ports through `${HOST_IP:-192.168.10.20}`, shares the Tailscale network namespace with Omni, and passes Omni v1.4 SQLite storage through `OMNI_SQLITE_PATH`.

The Proxmox provider compose currently uses the local patched image as described by the high-level gotchas: `ghcr.io/siderolabs/omni-infra-provider-proxmox:local-fix` is present in `proxmox-provider/compose.yml`, and the provider ID defaults to `matrix-cluster`.

The production cluster template exists at `clusters/talos-prod-01.yaml`, disables the default CNI, disables kube-proxy, uses Kubernetes `v1.35.0` and Talos `v1.12.1`, and defines three worker groups pinned to Foxtrot, Golf, and Hotel. Each worker group carries the documented Longhorn `/var/lib/longhorn` bind mount patch.

The disaster recovery README mostly matches `scripts/disaster-recovery.sh`: the configured timeouts, 10-second polling interval, cluster name, host list, and GitOps bootstrap path all match the script.

The Cilium MTU cross-reference is confirmed in the sibling GitOps repo. `mothership-gitops/README.md` installs Cilium with `--set MTU=1450` and explicitly documents the Omni siderolink MTU failure mode before the install command.

Several Longhorn GitOps claims are now confirmed from the sibling repo. `mothership-gitops/apps/root.yaml` defines the root Longhorn Application at sync wave 5 and ArgoCD HA at wave 99. `mothership-gitops/apps/longhorn/application.yaml` sets `defaultReplicaCount: 2`, `persistence.defaultClass: true`, `defaultClassReplicaCount: 2`, `backupTarget: "s3://longhorn-backups@us-east-1/"`, and `backupTargetCredentialSecret: "longhorn-backup-credentials"`. `apps/longhorn/externalsecret.yaml` pulls MinIO credentials from the `infisical-longhorn` ClusterSecretStore, and `apps/external-secrets/clustersecretstore.yaml` maps that store to Infisical path `/longhorn`.

## Human Review Queue

- Confirm live cluster state for Longhorn: default StorageClass, PVC inventory, backup target, ESO backup credentials, recurring jobs, and restore test status. The local repo documents these as current, but the backing artifacts are in a separate GitOps repo or the live cluster.
- Confirm the current deployed provider container name on the host. The checked-in compose uses `proxmox-provider`, while the DR script and scripts README refer to `omni-provider-proxmox-provider-1`.
- Confirm whether the `TS_EXTRA_ARGS=--advertise-tags=tag:omni` requirement is still operationally required. If yes, the local compose/env examples are missing it; if no, `docs/DEPLOYMENT.md` should drop that prerequisite.
- Verify external/upstream claims in `docs/references/providerdata-fields.md`, especially PR #36 merge status and field defaults. Local machine-class files use many of the listed fields, but the defaults are provider-source claims rather than repo-source claims.

## Suggested Fix Order

1. Update `docs/OPERATIONS.md` first. It has the highest concentration of commands that will fail immediately in this repository.
2. Reconcile all Proxmox provider references against `proxmox-provider/compose.yml`, `proxmox-provider/.env.example`, and `proxmox-provider/config.yaml.example`.
3. Update `docs/components/longhorn-storage.md` against `mothership-gitops/apps/longhorn/application.yaml`, `recurringjobs.yaml`, `storageclasses.yaml`, and `docs/backup-storage.md`.
4. Remove or replace the stale `specs/` and `pending/` references in `README.md`, `CLAUDE.md`, and `docs/ROADMAP.md`.
5. Decide whether `docs/DEPLOYMENT.md` is a historical runbook or the current install runbook. If current, refresh both compose snippets from checked-in files.
6. Do a live-cluster pass for remaining runtime claims that cannot be verified from local or sibling repositories alone.
