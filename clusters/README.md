# Clusters

Omni cluster templates for deploying Talos Kubernetes clusters.

## Template Structure

Cluster templates use multi-document YAML with separate sections for each resource type:

```yaml
kind: Cluster
name: my-cluster
labels:
  environment: production
kubernetes:
  version: v1.34.2
talos:
  version: v1.12.0
patches:
  - name: disable-default-cni
    inline:
      cluster:
        network:
          cni:
            name: none
        proxy:
          disabled: true
---
kind: ControlPlane
machineClass:
  name: control-plane
  size: 3
systemExtensions:
  - siderolabs/iscsi-tools
  - siderolabs/util-linux-tools
---
kind: Workers
machineClass:
  name: worker
  size: 3
systemExtensions:
  - siderolabs/iscsi-tools
patches:
  - name: worker-labels
    inline:
      machine:
        nodeLabels:
          node-role.kubernetes.io/worker: ""
```

## Resource Types

### Cluster

Defines the cluster name, versions, and cluster-wide patches.

| Field | Description |
|-------|-------------|
| `name` | Cluster identifier |
| `labels` | Cluster-level labels (key-value pairs) |
| `kubernetes.version` | Kubernetes version (e.g., v1.34.2) |
| `talos.version` | Talos Linux version (e.g., v1.11.5) |
| `patches` | Cluster-wide Talos machine config patches |

### ControlPlane

Defines control plane nodes. Use odd numbers (1, 3, 5) for etcd quorum stability.

| Field | Description |
|-------|-------------|
| `machineClass.name` | Machine class to provision from |
| `machineClass.size` | Number of control plane nodes |
| `machines` | Alternative: list of specific machine UUIDs |
| `systemExtensions` | Talos system extensions to install |

Note: `machines` and `machineClass` are mutually exclusive.

### Workers

Defines worker nodes. Multiple worker sets can be defined with different names.

| Field | Description |
|-------|-------------|
| `name` | Worker set name (default: `workers`). Must be unique, allows letters, digits, `-`, `_`. |
| `machineClass.name` | Machine class to provision from |
| `machineClass.size` | Number of workers (can be `unlimited` for autoscaling) |
| `machines` | Alternative: list of specific machine UUIDs |
| `systemExtensions` | Talos system extensions to install |
| `patches` | Worker-specific Talos machine config patches |
| `updateStrategy` | Rolling update configuration |
| `deleteStrategy` | Rolling delete configuration |

## Patches

Patches can be inline or file-based:

```yaml
patches:
  # Inline patch
  - name: my-patch
    inline:
      machine:
        nodeLabels:
          custom-label: "value"
  # File-based patch
  - file: patches/custom-config.yaml
```

## Common System Extensions

| Extension | Purpose |
|-----------|---------|
| `siderolabs/iscsi-tools` | iSCSI support (Longhorn, etc.) |
| `siderolabs/nfsd` | NFS server support |
| `siderolabs/util-linux-tools` | Linux utilities |
| `siderolabs/qemu-guest-agent` | QEMU/Proxmox guest agent |
| `siderolabs/nonfree-kmod-nvidia` | NVIDIA kernel modules |
| `siderolabs/nvidia-container-toolkit` | NVIDIA container runtime |

## Commands

```bash
# Validate template (offline)
omnictl cluster template validate -f clusters/test-cluster.yaml

# Preview changes
omnictl cluster template diff -f clusters/test-cluster.yaml

# Apply template
omnictl cluster template sync -f clusters/test-cluster.yaml

# Check cluster status
omnictl cluster template status -f clusters/test-cluster.yaml

# Export existing cluster as template
omnictl cluster template export <cluster-name>

# Delete cluster resources
omnictl cluster template delete -f clusters/test-cluster.yaml
```

## Example: Production Cluster with GPU Workers

```yaml
kind: Cluster
name: talos-prod-cluster
labels:
  cluster-id: "1"
kubernetes:
  version: v1.34.2
talos:
  version: v1.12.0
patches:
  - name: disable-default-cni
    inline:
      cluster:
        network:
          cni:
            name: none
        proxy:
          disabled: true
---
kind: ControlPlane
machineClass:
  name: proxmox-control-plane
  size: 3
systemExtensions:
  - siderolabs/iscsi-tools
  - siderolabs/nfsd
  - siderolabs/util-linux-tools
---
kind: Workers
name: workers
machineClass:
  name: proxmox-worker
  size: 3
systemExtensions:
  - siderolabs/iscsi-tools
  - siderolabs/nfsd
  - siderolabs/util-linux-tools
patches:
  - name: worker-labels
    inline:
      machine:
        nodeLabels:
          node-role.kubernetes.io/worker: ""
  - name: longhorn-storage
    inline:
      machine:
        kubelet:
          extraMounts:
            - destination: /var/lib/longhorn
              type: bind
              source: /var/local/longhorn
              options:
                - bind
                - rshared
                - rw
---
kind: Workers
name: gpu-workers
machineClass:
  name: proxmox-gpu-worker
  size: 1
systemExtensions:
  - siderolabs/iscsi-tools
  - siderolabs/nfsd
  - siderolabs/util-linux-tools
  - siderolabs/nonfree-kmod-nvidia
  - siderolabs/nvidia-container-toolkit
patches:
  - name: worker-labels
    inline:
      machine:
        nodeLabels:
          node-role.kubernetes.io/worker: ""
  - file: patches/gpu-worker.yaml
  - name: longhorn-storage
    inline:
      machine:
        kubelet:
          extraMounts:
            - destination: /var/lib/longhorn
              type: bind
              source: /var/local/longhorn
              options:
                - bind
                - rshared
                - rw
```

## Example: Update/Delete Strategies

```yaml
kind: Workers
name: workers
machineClass:
  name: worker
  size: 10
updateStrategy:
  rolling:
    maxParallelism: 3
deleteStrategy:
  type: Rolling
  rolling:
    maxParallelism: 5
```

## Reference

- [Cluster Templates - Sidero Documentation](https://omni.siderolabs.com/reference/cluster-templates)
