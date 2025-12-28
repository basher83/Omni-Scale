---
name: provider-status
description: Check Proxmox provider status and verify connectivity
allowed-tools: Bash, Read, Edit
---

# Provider Status

Check the health of the Proxmox infrastructure provider and verify connectivity.

## Docker Service Status

Check all services are running:

```bash
docker compose -f ${CLAUDE_PROJECT_DIR}/docker/compose.yaml ps
```

Report the status of each service:

- `omni-tailscale` - Should be healthy
- `omni` - Should be running
- `proxmox-provider` - Should be running

If any service is not running or unhealthy, report the issue.

## Provider Logs

Check recent provider logs for errors:

```bash
docker compose -f ${CLAUDE_PROJECT_DIR}/docker/compose.yaml logs --tail=30 proxmox-provider
```

Look for:

- Registration confirmation messages
- Error messages or warnings
- Connection issues

## Proxmox API Connectivity

Read `${CLAUDE_PROJECT_DIR}/docker/config.yaml` to get the Proxmox URL.

Test API connectivity (if curl is available):

```bash
curl -k -s -o /dev/null -w "%{http_code}" <proxmox-url>/version
```

Report:

- 200: API reachable
- 401/403: Authentication issue
- Connection refused: Network issue

## Omni Connection

Check if provider is registered in Omni by looking for registration confirmation in logs.

## Update State File

Read `${CLAUDE_PROJECT_DIR}/.claude/omni-scale.local.md` if it exists.

Update frontmatter:

- `provider_status`: Set to `healthy`, `unhealthy`, or `unknown` based on checks
- `last_verified`: Current ISO timestamp

## Summary

Report to user:

| Check | Status |
|-------|--------|
| Docker services | Running/Stopped |
| Provider registration | Registered/Not registered |
| Proxmox API | Reachable/Unreachable |
| Overall health | Healthy/Unhealthy |

If unhealthy, suggest:

- Check `${CLAUDE_PROJECT_DIR}/docker/TROUBLESHOOTING.md` for deployment issues
- Check `${CLAUDE_PLUGIN_ROOT}/skills/omni-proxmox/references/troubleshooting.md` for operational issues
