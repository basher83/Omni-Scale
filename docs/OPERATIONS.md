# Omni-Scale Operations Guide

Day-to-day management of Sidero Omni clusters via CLI tools.

**Prerequisites:** Omni Hub and Worker deployed per [DEPLOYMENT.md](./DEPLOYMENT.md)

---

## Repo Boundary

This guide covers Omni, Talos, cluster templates, machine classes, and the
Proxmox infrastructure provider. ArgoCD applications, Longhorn backups,
StorageClasses, External Secrets, Tailscale Operator manifests, ingress
exposure, and workload operations are owned by `../mothership-gitops`.

After the cluster is reachable and the bootstrap command has been applied,
use `../mothership-gitops/README.md` and `../mothership-gitops/docs/` for
platform operations.

Keep this repo as a handoff pointer, not a mirror of GitOps state. The current
GitOps source-of-truth entry points are:

- Bootstrap: `../mothership-gitops/bootstrap/bootstrap.yaml`
- App of Apps: `../mothership-gitops/apps/root.yaml`
- Longhorn Helm values: `../mothership-gitops/apps/longhorn/application.yaml`
- Longhorn backup schedules: `../mothership-gitops/apps/longhorn/recurringjobs.yaml`
- Longhorn StorageClasses: `../mothership-gitops/apps/longhorn/storageclasses.yaml`
- Backup storage docs: `../mothership-gitops/docs/backup-storage.md`
- ArgoCD HA: `../mothership-gitops/apps/argocd/` and
  `../mothership-gitops/apps/root.yaml`

---

## 1. CLI Installation

### Install via Homebrew (macOS)

This method keeps tools updated automatically. Installs `omnictl`, `talosctl`, and `kubectl-oidc-login`.

```bash
brew install siderolabs/tap/sidero-tools
```

### Verify Installation

```bash
omnictl version
talosctl version --client
```

---

## 2. Configuration

### Config File Locations

| Tool | Config Path |
|------|-------------|
| omnictl | `~/.talos/omni/config` |
| talosctl | `~/.talos/config` |

> **Note:** Sidero docs show different paths—these are correct for Homebrew installs.

### Download Config from Omni UI

1. Log in to Omni Dashboard
2. Navigate to **Settings** → **Download omniconfig.yaml**
3. Move to config location:

```bash
cp omniconfig.yaml ~/.talos/omni/config
```

### Merge with Existing Config

If you have an existing configuration:

```bash
omnictl config merge ./omniconfig.yaml
```

### Verify Contexts

```bash
omnictl config contexts
```

---

## 3. Authentication

### Trigger OIDC Flow

```bash
omnictl get clusters
```

A browser window opens for sign-in. If it doesn't:

```bash
BROWSER=echo omnictl get clusters
```

Copy the URL manually and complete sign-in. Credentials are cached locally after authentication.

### Generate New Config (Alternative)

```bash
omnictl config new --url https://omni.spaceships.work > ~/.talos/omni/config
```

> **Note:** For OIDC/Auth0, this triggers browser authentication.

### Project-Local Config (Optional)

Keep config relative to your project:

```bash
export OMNICONFIG=$(pwd)/omni/omni.config
omnictl config new --url https://omni.spaceships.work > $OMNICONFIG
```

---

## 4. Machine Classes

Machine classes define VM specs for Proxmox provisioning.

### Apply Machine Classes

```bash
omnictl apply -f machine-classes/matrix-control-plane.yaml
omnictl apply -f machine-classes/matrix-worker-foxtrot.yaml
omnictl apply -f machine-classes/matrix-worker-golf.yaml
omnictl apply -f machine-classes/matrix-worker-hotel.yaml
```

### Verify

```bash
omnictl get machineclasses
```

### Example Machine Class

```yaml
# machine-classes/matrix-control-plane.yaml
metadata:
  namespace: default
  type: MachineClasses.omni.sidero.dev
  id: matrix-control-plane
spec:
  autoprovision:
    providerid: matrix-cluster
    providerdata: |
      cores: 4
      memory: 8192
      storage_selector: name == "local-lvm"
```

---

## 5. Cluster Management

### Sync Cluster Template

```bash
omnictl cluster template sync -v -f clusters/talos-prod-01.yaml
```

### Create Cluster

**Via CLI:**

```bash
omnictl cluster template sync -v -f clusters/talos-prod-01.yaml
```

**Via UI:**

1. Navigate to **Clusters** → **Create New Cluster**
2. Select Machine Classes for Control Plane and Workers
3. Configure cluster settings
4. Create

### List Clusters

```bash
omnictl get clusters
```

### Watch Cluster Status

```bash
omnictl get machines -w
```

---

## 6. Troubleshooting Provisioning

### Provider Logs

```bash
cd proxmox-provider
docker compose logs -f proxmox-provider
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Machines not appearing | `storage_selector` mismatch | Verify storage pool name matches Proxmox |
| Provider disconnected | Service account key invalid | Regenerate key in Omni UI |
| VM creation fails | Proxmox API token permissions | Check token has VM.Allocate, VM.Clone, Datastore.AllocateSpace |

### Verify Provider Connection

```bash
omnictl get infraproviders
```

---

## 7. Day 2 Operations

### Upgrade Omni Hub

The Hub version gates which Talos and Kubernetes versions Omni will accept —
upgrade it before bumping cluster templates. Read the "Urgent Upgrade Notes"
in the [Omni release notes](https://github.com/siderolabs/omni/releases) for
every minor version you skip.

On the Omni host, from `omni/`:

```bash
# Set the new version
$EDITOR omni.env   # OMNI_IMG_TAG=vX.Y.Z

# --env-file is required: compose interpolates ${OMNI_IMG_TAG} at parse
# time and the env file is not named .env. Never use `down -v` (deletes
# Tailscale state).
docker compose --env-file omni.env pull
docker compose --env-file omni.env up -d --force-recreate
```

Verify:

```bash
omnictl get sysversion -o jsonpath='{.spec.backendversion}'
omnictl get talosversions   # new versions should appear
```

Keep `omni.env.example` and the `omnictl` pin in `mise.toml` in sync with
the deployed version.

### Upgrade Talos Nodes

```bash
# Check available versions
omnictl get talosversions

# Trigger upgrade via UI or sync the updated cluster template
omnictl cluster template sync -v -f clusters/talos-prod-01.yaml
```

### Scale Cluster

Update machine count in cluster template and re-sync:

```bash
omnictl cluster template sync -v -f clusters/talos-prod-01.yaml
```

### Access Cluster via kubectl

```bash
# Get kubeconfig (uses OIDC)
omnictl kubeconfig -c <cluster-name> > kubeconfig.yaml

# Use it
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
```

---

## Quick Reference

| Task | Command |
|------|---------|
| List clusters | `omnictl get clusters` |
| List machines | `omnictl get machines` |
| List machine classes | `omnictl get machineclasses` |
| Watch provisioning | `omnictl get machines -w` |
| Get kubeconfig | `omnictl kubeconfig -c <name>` |
| Check providers | `omnictl get infraproviders` |
| Sync template | `omnictl cluster template sync -v -f <file>` |
