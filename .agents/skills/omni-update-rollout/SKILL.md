---
name: omni-update-rollout
description: >
  Roll Talos, Kubernetes, or Omni version updates through the substrate in
  dependency order — renovate triage, live-backend compatibility gating, and
  split Talos-then-Kubernetes cluster rollout with health gates.
when_to_use: >
  Use when triaging renovate branches or PRs on Omni-Scale, checking whether a
  Talos/Kubernetes bump is safe to apply, or executing a cluster template
  version rollout on talos-prod-01.
---

# Omni Substrate Update Rollout

Roll version updates through the substrate in dependency order: Omni Hub gates
Talos, Talos gates Kubernetes. The repo is desired state; the live backend is
truth. Never merge a version bump the running control plane would reject.

## Guardrails

- Never trust repo pins or PR titles for compatibility — verify against the
  live backend (`omnictl get talosversions`), which is the only authority on
  what Omni will accept.
- Desired state first: template edits are committed and pushed to main
  *before* `omnictl cluster template sync`. The cluster never runs anything
  main doesn't describe.
- Split rollouts: Talos and Kubernetes bumps are separate commits and separate
  syncs, with a health gate between. Never apply both halves in one sync.
- Never migrate Talos VMs. A stuck node is destroy/recreate, per doctrine.
- The provider image `omni-infra-provider-proxmox:local-fix` is a locally
  patched fork — exempt from all version automation.

## Workflow

### 1. Triage

```bash
git fetch --prune
gh pr list --state open
git diff main...origin/renovate/<branch>   # for each renovate branch
```

Note PR age — a long-stale renovate PR usually means a hidden gate, not a
forgotten merge. Trivial PRs (action digest pins, mise tool bumps) merge
squash-style now; keep the `omnictl` mise pin matched to the Hub version.

### 2. Compatibility gate (live backend)

```bash
omnictl get sysversion -o jsonpath='{.spec.backendversion}'
omnictl get talosversions -o jsonpath='{.metadata.id}' | grep '^<target-talos>'
omnictl get talosversion <target-talos> -o yaml | grep '<target-k8s>'
```

If the target Talos/K8s versions are absent, the Hub is the blocker — use the
**omni-upgrade** skill first, then re-run this gate. If present, continue.

### 3. Pre-flight (before touching the template)

- Talos release notes for the target minor: scan for breaking changes
  touching machine config, CNI, or extensions.
- Extensions exist for the target:
  `omnictl get talosextensions <ver> -o yaml | grep <each extension in template>`
- `omnictl get etcdbackupstatus` — if empty, flag it to the operator before a
  control-plane change; proceed only with acknowledgment.
- `omnictl cluster status <cluster>` — start from `RUNNING Ready`, all
  machines healthy. Never roll onto a degraded cluster.

### 4. Talos half

```bash
# edit clusters/<cluster>.yaml: talos.version only
omnictl cluster template validate -f clusters/<cluster>.yaml
git commit && git push          # desired state lands first
omnictl cluster template sync -v -f clusters/<cluster>.yaml
```

Monitor by polling `omnictl cluster status <cluster>`. For completion, check
per-machine versions — not the cluster Ready line, which races the next
phase:

```bash
omnictl get machinestatus -o json | jq -r '"\(.spec.network.hostname) \(.spec.talosversion)"'
```

### 5. Health gate

All must pass before the Kubernetes half:

```bash
kubectl get nodes                                        # all Ready, target Talos
kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.mtu}'   # must be 1450
kubectl -n kube-system get ds cilium                     # N/N ready
kubectl -n longhorn-system get volumes.longhorn.io -o json | \
  jq -r '[.items[].status.robustness] | group_by(.) | map("\(.[0]): \(length)") | join(", ")'
```

Degraded Longhorn volumes after rolling reboots are normal — replicas
rebuilding. **Wait for 0 degraded** before proceeding; check engine
`rebuildStatus` for progress and errors. MTU not 1450 means the Cilium
config was clobbered — stop and fix per `docs/guides/CILIUM.md`.

### 6. Kubernetes half

Same as step 4 with `kubernetes.version`, its own commit, its own sync.
No node reboots — staged control-plane components then kubelets. Completion:
`kubectl get nodes` shows the target version on every node. Re-run the
step-5 health checks.

### 7. Close out

- Close the renovate PR with a comment stating what was applied and any
  ordering it required (`gh pr close <n> --comment "..." --delete-branch`),
  or let renovate auto-close on rebase.
- If the rollout changed operational commands or version pins anywhere else
  (docs, env examples, mise), sync them in the same session — stale copies
  of version facts are how the next stall starts.

## Failure handling

- Sync rejected for an unsupported version: the gate was skipped or raced —
  re-run step 2, do not retry the sync.
- A machine stuck mid-upgrade: investigate via Omni; if the node is wedged,
  destroy/recreate from spec. Never migrate, never hand-patch a node.
- Health gate fails: stop the rollout where it is. A half-rolled cluster in
  a known state beats a fully-rolled cluster in an unknown one.
