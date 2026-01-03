# Omni-Scale Operations Guide

Day-to-day management of Sidero Omni clusters via CLI tools.

**Prerequisites:** Omni Hub and Worker deployed per [Sidero_Omni_Runbook.md](./Sidero_Omni_Runbook.md)

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
omnictl apply -f machine-classes/control-plane.yaml
omnictl apply -f machine-classes/worker.yaml
```

### Verify

```bash
omnictl get machineclasses
```

### Example Machine Class

```yaml
# machine-classes/control-plane.yaml
kind: MachineClass
metadata:
  name: control-plane
spec:
  # TODO: Add your machine class spec
```

---

## 5. Cluster Management

### Sync Cluster Template

```bash
omnictl cluster template sync -v -f cluster-template.yaml
```

### Create Cluster

**Via CLI:**

```bash
omnictl apply -f clusters/my-cluster.yaml
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
docker compose logs -f omni-infra-provider-proxmox
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

### Upgrade Talos Nodes

```bash
# Check available versions
omnictl get talosversions

# Trigger upgrade via UI or apply updated cluster template
omnictl cluster template sync -v -f cluster-template.yaml
```

### Scale Cluster

Update machine count in cluster template and re-sync:

```bash
omnictl cluster template sync -v -f cluster-template.yaml
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
