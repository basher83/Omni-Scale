---
name: cluster-status
description: Check status of Omni-managed Kubernetes clusters
allowed-tools: Bash, Read
argument-hint: [cluster-name]
---

# Cluster Status

Check the status of Omni-managed Kubernetes clusters.

## Omni Endpoint

```
https://omni.spaceships.work
```

## Check omnictl

Verify omnictl is available:

```bash
command -v omnictl || ls ~/.local/bin/omnictl
```

If not found, suggest installation:

```bash
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
mkdir -p ~/.local/bin
curl -fsSL "https://github.com/siderolabs/omni/releases/latest/download/omnictl-${OS}-${ARCH}" -o ~/.local/bin/omnictl
chmod +x ~/.local/bin/omnictl
```

## Authentication

Check for `OMNICTL_SERVICE_ACCOUNT_KEY` environment variable. If not set, suggest:

1. Run `omnictl --omni-url https://omni.spaceships.work login` for interactive Auth0 flow
2. Or set `OMNICTL_SERVICE_ACCOUNT_KEY` for automation

See `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/omnictl-auth.md` for setup.

## List Clusters

If no cluster name provided (`$1` empty), list all clusters:

```bash
omnictl --omni-url https://omni.spaceships.work get clusters
```

## Cluster Details

If cluster name provided, get detailed status:

```bash
omnictl --omni-url https://omni.spaceships.work get cluster $1 -o yaml
```

## Machine Status

List machines in the cluster:

```bash
omnictl --omni-url https://omni.spaceships.work get machines --cluster $1
```

Report:

- Total machines
- Healthy vs unhealthy count
- Control plane vs worker breakdown

## Cluster Health

Check cluster health:

```bash
omnictl --omni-url https://omni.spaceships.work cluster status $1
```

Common issues:

- Control plane quorum (need 1 or 3 control plane nodes)
- Machine health status
- Kubernetes API availability

## Get Kubeconfig

If cluster is healthy, offer to get kubeconfig:

```bash
omnictl --omni-url https://omni.spaceships.work kubeconfig $1 -o ~/.kube/$1.yaml
```

## Summary

Report cluster overview:

| Cluster | Status | Control Plane | Workers |
|---------|--------|---------------|---------|
| name | Healthy/Unhealthy | X/Y ready | X/Y ready |

If issues found, suggest:

- Check machine logs in Omni UI
- Review `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/troubleshooting.md`
- Run `/provider-status` to verify provider health
