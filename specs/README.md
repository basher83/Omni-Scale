# Specs

Declarative infrastructure specifications defining desired state.

## Philosophy

Specs are the **source of truth** for what should exist. They capture:
- Target architecture and configuration
- Constraints and locked decisions
- Dependencies between components
- Optionally, current deployment status

Specs do NOT contain implementation details (that's what `terraform/`, `ansible/`, etc. are for).

## Schema

```yaml
apiVersion: homelab/v1
kind: <ComponentType>
metadata:
  name: <unique-identifier>
  description: <human-readable description>

spec:
  # Component-specific configuration
  # This varies by kind

dependencies:
  # Optional: explicit dependencies
  - name: <other-component>
    type: <hard|soft>  # hard = blocker, soft = preferred order

decisions:
  # Locked decisions that are non-negotiable
  - key: <decision-name>
    value: <decision-value>
    rationale: <why this decision was made>

status:
  # Optional: track deployment state in spec
  phase: Planning | Implementing | Deployed | Deprecated
  lastUpdated: <ISO-8601 date>
  blockedBy: <optional: what's blocking progress>
  notes: <optional: current state notes>
```

## Component Types (kind)

| Kind | Description |
|------|-------------|
| `Platform` | Top-level platform (e.g., Omni, Kubernetes distribution) |
| `Cluster` | Kubernetes cluster definition |
| `Node` | Individual node (VM, LXC, bare metal) |
| `Provider` | Infrastructure provider (Proxmox provider, cloud provider) |
| `Network` | Network configuration (VLANs, routes, DNS) |
| `Storage` | Storage configuration (CEPH, NFS, local) |
| `Service` | Deployed service/application |

## Example: Omni Platform Spec

```yaml
apiVersion: homelab/v1
kind: Platform
metadata:
  name: omni
  description: Sidero Omni Kubernetes management platform

spec:
  provider:
    name: omni-provider
    type: lxc
    host: foxtrot
    ip: 192.168.3.10/24
    gateway: 192.168.3.1
    resources:
      cores: 1
      memory: 1024
      disk: 4
    networking:
      - vmbr0  # LAN access
      - tailscale  # Omni connectivity

  clusters:
    - name: talos-prod
      controlPlane:
        count: 3
        host: pve-matrix-01
      workers:
        count: 2
        host: pve-nexus-01

decisions:
  - key: provider-location
    value: foxtrot (Matrix cluster)
    rationale: Provider must be L2-adjacent to booting VMs for SideroLink registration
  - key: deployment-type
    value: LXC
    rationale: Lightweight, sufficient for provider workload

status:
  phase: Planning
  lastUpdated: 2025-12-30
  blockedBy: Provider relocation
  notes: Provider currently on Holly (Quantum), needs to move to Matrix
```

## Usage

Analyze a spec and generate deployment plan:

```bash
claude
> /analyze-spec specs/omni.yaml
```

## Files

| File | Description | Status |
|------|-------------|--------|
| `omni.yaml` | Omni platform deployment | Active |
