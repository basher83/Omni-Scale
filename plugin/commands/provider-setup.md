---
name: provider-setup
description: Verify Proxmox infrastructure provider configuration and connectivity
allowed-tools: Bash, Read
---

# Provider Setup Verification

Verify the Proxmox infrastructure provider is properly configured and connected to Omni.

## Current Architecture

The provider runs on Foxtrot LXC (VMID 200), managed by the infrastructure team. This command verifies connectivity, not deployment.

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

If not found, suggest installation:

```bash
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
mkdir -p ~/.local/bin
curl -fsSL "https://github.com/siderolabs/omni/releases/latest/download/omnictl-${OS}-${ARCH}" -o ~/.local/bin/omnictl
chmod +x ~/.local/bin/omnictl
```

## Check Provider Registration

Query Omni for registered infrastructure providers:

```bash
omnictl --omni-url https://omni.spaceships.work get infraproviders
```

Look for:

- Provider ID: `Proxmox`
- Status: `Connected` or `Ready`

## Verify Provider Can List Resources

If provider is registered, it should be able to enumerate Proxmox resources. Check provider logs (requires SSH access to Foxtrot LXC):

```bash
ssh omni-provider docker logs --tail=20 omni-provider-proxmox-provider-1
```

Look for successful storage pool enumeration or VM creation messages.

## Summary

Report to user:

| Check | Status |
|-------|--------|
| omnictl available | Yes/No |
| Provider registered | Registered/Not found |
| Provider status | Connected/Disconnected |

If provider not registered or unhealthy:

- Contact infrastructure team
- Check provider logs on Foxtrot LXC
- See `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/troubleshooting.md`
