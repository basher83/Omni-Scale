---
name: provider-status
description: Check Proxmox provider status via Omni API
allowed-tools: Bash, Read
---

# Provider Status

Check the health of the Proxmox infrastructure provider.

## Current Architecture

| Component | Location |
|-----------|----------|
| Omni | Holly (omni.spaceships.work) |
| Provider | Foxtrot LXC (192.168.3.10) |
| Proxmox API | 192.168.3.5:8006 |

## Check omnictl

Verify omnictl is available:

```bash
command -v omnictl || ls ~/.local/bin/omnictl
```

## Provider Registration Status

Query Omni for infrastructure providers:

```bash
omnictl --omni-url https://omni.spaceships.work get infraproviders
```

Expected output shows `Proxmox` provider with status.

## Provider Details

Get detailed provider information:

```bash
omnictl --omni-url https://omni.spaceships.work get infraprovider Proxmox -o yaml
```

## Machine Classes

List registered machine classes (confirms provider is functional):

```bash
omnictl --omni-url https://omni.spaceships.work get machineclasses
```

## Recent Machine Activity

Check for any machines managed by the provider:

```bash
omnictl --omni-url https://omni.spaceships.work get machines
```

## Provider Logs (Optional)

If SSH access to Foxtrot LXC is available:

```bash
ssh omni-provider docker logs --tail=30 omni-provider-proxmox-provider-1
```

Look for:

- Registration confirmation messages
- Error messages or warnings
- VM provisioning activity

## Summary

Report to user:

| Check | Status |
|-------|--------|
| Provider registered | Yes/No |
| Provider status | Connected/Disconnected |
| Machine classes | Count |
| Active machines | Count |

If unhealthy, suggest:

- Check provider logs on Foxtrot LXC
- Review `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/troubleshooting.md`
- Contact infrastructure team if provider is down
