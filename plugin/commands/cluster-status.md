---
name: cluster-status
description: Check status of Omni-managed Kubernetes clusters
allowed-tools: Bash, Read, Edit
argument-hint: [cluster-name]
---

# Cluster Status

Check the status of Omni-managed Kubernetes clusters.

## Check omnictl

Verify omnictl is available:

```bash
command -v omnictl || ls ~/.local/bin/omnictl
```

If not found, suggest running `/machineclass-create` first (which installs omnictl) or manual installation.

## Get Omni Endpoint

Read `${CLAUDE_PROJECT_DIR}/.claude/omni-scale.local.md` for `omni_endpoint`.

If not available, ask user for Omni URL.

## Authentication

Check for `OMNICTL_SERVICE_ACCOUNT_KEY` environment variable. If not set, suggest:

1. Run `omnictl login` for interactive OIDC flow, or
2. Set `OMNICTL_SERVICE_ACCOUNT_KEY` for automation

See `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/omnictl-auth.md` for setup.

## List Clusters

If no cluster name provided (`$1` empty), list all clusters:

```bash
omnictl --omni-url <endpoint> get clusters
```

## Cluster Details

If cluster name provided, get detailed status:

```bash
omnictl --omni-url <endpoint> get cluster $1 -o yaml
```

## Machine Status

List machines in the cluster:

```bash
omnictl --omni-url <endpoint> get machines --cluster $1
```

Report:

- Total machines
- Healthy vs unhealthy count
- Control plane vs worker breakdown

## Cluster Health

Check for common issues:

- Control plane quorum (need 1 or 3 control plane nodes)
- Machine health status
- Kubernetes API availability

## Update State File

Read `${CLAUDE_PROJECT_DIR}/.claude/omni-scale.local.md` if it exists.

Update frontmatter:

- `active_clusters`: List of cluster names found

## Summary

Report cluster overview:

| Cluster | Status | Control Plane | Workers |
|---------|--------|---------------|---------|
| name | Healthy/Unhealthy | X/Y ready | X/Y ready |

If issues found, suggest:

- Check machine logs in Omni UI
- Review `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/troubleshooting.md`
- Run `/provider-status` to verify provider health
