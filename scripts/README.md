# Scripts

Automation scripts for Omni-Scale infrastructure management.

## disaster-recovery.sh

Automated cluster destruction and recreation from declarative specs. Executes the full DR drill without human intervention (after initial confirmation).

### Usage

```bash
./scripts/disaster-recovery.sh
```

### Prerequisites

- `omnictl` authenticated
- `kubectl` available
- `jq` installed
- SSH access to `omni-provider` via Tailscale
- Infisical credentials available (for secret recreation)
- Cluster template exists at configured path

### Phases

| Phase | Action | Timeout |
|-------|--------|---------|
| 3 | Delete cluster, wait for VM cleanup across all Proxmox hosts | 10 min |
| 4 | Apply cluster template, wait for all machines running | 20 min |
| 5a | Wait for Kubernetes API availability | 10 min |
| 5b | Wait for all nodes Ready | 10 min |
| 6a | Apply GitOps bootstrap, wait for ArgoCD available | 5 min |
| 6b | Wait for all apps Synced/Healthy (except argocd-ha) | 20 min |

Total expected runtime: 30-45 minutes.

### Interactive Points

**Start confirmation:** Script requires typing `yes` to proceed. This is the only interactive prompt under normal operation.

**Secret creation (conditional):** If `universal-auth-credentials` secret doesn't exist in `external-secrets` namespace, script pauses and provides the command to create it. This is the one secret that cannot be automated (Infisical bootstrap chicken-and-egg).

### Features

**Poll-based waiting:** Each phase uses `poll_until()` function that checks a condition every 10 seconds until success or timeout. No human judgment required mid-run.

**Failure diagnostics:** On timeout, each phase runs diagnostic commands and reports what's stuck:
- VM cleanup: Lists remaining VMs per Proxmox host
- Machine provisioning: Shows machine phases + provider logs
- Node health: Describes node conditions
- App sync: Lists apps with sync/health status

**Multi-host VM monitoring:** Checks for Talos VMs across foxtrot, golf, and hotel (all Matrix cluster hosts), not just a single node.

**Phase gating:** Each phase must complete successfully before the next begins. Failure exits immediately with diagnostics.

**Timing summary:** Final output shows cumulative time per phase and total runtime.

### Configuration

Paths and timeouts are configured at the top of the script:

```bash
CLUSTER_NAME="talos-prod-01"
CLUSTER_TEMPLATE="${HOME}/dev/infra-as-code/Omni-Scale/clusters/talos-prod-01.yaml"
GITOPS_BOOTSTRAP="${HOME}/dev/infra-as-code/mothership-gitops/bootstrap/bootstrap.yaml"
```

Adjust paths if your directory structure differs.

### Post-Recovery

After script completes:

1. All nodes should be Ready
2. All ArgoCD apps should be Synced/Healthy (except argocd-ha)
3. ArgoCD HA requires manual sync if desired:
   ```bash
   argocd app sync argocd-ha
   ```

### Failure Scenarios

| Symptom | Likely Cause | Check |
|---------|--------------|-------|
| VMs not destroying | Omni/Provider issue | Check Omni console for errors |
| VMs not provisioning | Provider disconnected, key expired | `ssh omni-provider "docker logs omni-provider-proxmox-provider-1"` |
| Nodes not joining | DNS resolution wrong | Verify split-horizon DNS returns LAN IP |
| Apps not syncing | ESO/Infisical issue | Check ClusterSecretStore health |

## proxmox-vm-optimize.sh

VM disk and GPU optimization for Proxmox. See script header for usage.
