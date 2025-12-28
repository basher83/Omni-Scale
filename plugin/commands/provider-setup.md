---
name: provider-setup
description: Configure the Proxmox infrastructure provider for Omni
allowed-tools: Bash, Write, Read, Edit
---

# Provider Setup

Configure the Proxmox infrastructure provider connection.

## Prerequisites Check

First verify required tools are available:

1. Check docker is installed: `docker --version`
2. Check docker compose is available: `docker compose version`

If either is missing, inform the user and stop.

## Configuration Files

Check for required configuration files in the `${CLAUDE_PROJECT_DIR}/docker/` directory:

1. Read `${CLAUDE_PROJECT_DIR}/docker/.env` - if missing, copy from `${CLAUDE_PROJECT_DIR}/docker/.env.example`
2. Read `${CLAUDE_PROJECT_DIR}/docker/config.yaml` - if missing, copy from `${CLAUDE_PROJECT_DIR}/docker/config.yaml.example`

## Environment Variables

Check `.env` for required variables:

- `TS_AUTHKEY` - Tailscale auth key
- `OMNI_DOMAIN` - Omni hostname
- `OMNI_INITIAL_USER` - First admin email
- `OIDC_ISSUER_URL` - tsidp URL
- `OIDC_CLIENT_ID` - OIDC client ID
- `OIDC_CLIENT_SECRET` - OIDC client secret
- `OMNI_INFRA_PROVIDER_KEY` - Infrastructure provider key

If `OMNI_INFRA_PROVIDER_KEY` is empty or placeholder:

1. Ask user if they have generated a provider key
2. If not, explain: "Generate key in Omni UI → Settings → Infrastructure Providers → Create"
3. Wait for user to provide the key
4. Update `.env` with the provided key

## Proxmox Configuration

Check `${CLAUDE_PROJECT_DIR}/docker/config.yaml` for Proxmox credentials:

- `proxmox.url` - API endpoint
- Authentication: either `tokenID`/`tokenSecret` OR `username`/`password`/`realm`

If values are placeholders, ask user for their Proxmox connection details.

## Start/Restart Stack

After configuration is complete:

```bash
docker compose -f ${CLAUDE_PROJECT_DIR}/docker/compose.yaml up -d
```

## Verify Registration

Wait 10 seconds, then check provider logs:

```bash
docker compose -f ${CLAUDE_PROJECT_DIR}/docker/compose.yaml logs --tail=20 proxmox-provider
```

Look for "registered" or "connected" messages. Report success or any errors.

## Update State File

Read `${CLAUDE_PROJECT_DIR}/.claude/omni-scale.local.md` if it exists. If not, create it from `${CLAUDE_PLUGIN_ROOT}/.claude/omni-scale.local.md.example`.

Update the state file frontmatter:

- `provider_status: healthy` (if registration successful)
- `last_verified: <current ISO timestamp>`
- Update `omni_endpoint` and `proxmox_endpoint` based on configuration

## Summary

Report to user:

- Provider configuration status
- Any warnings or issues found
- Next steps (run `/provider-status` to verify connectivity)
