# omnictl Authentication

The omnictl CLI requires authentication to communicate with Omni. Two methods are available.

## Option 1: Service Account Key (Recommended for Automation)

Service account keys provide non-interactive authentication for scripts and CI/CD.

### Creating a Service Account

1. Open Omni UI
2. Navigate to Settings → Service Accounts
3. Click "Create Service Account"
4. Set appropriate permissions (Admin, Operator, or Reader)
5. Copy the generated key

### Using the Key

**Environment variable:**

```bash
export OMNICTL_SERVICE_ACCOUNT_KEY="your-key-here"
export OMNICTL_ENDPOINT="https://omni.your-tailnet.ts.net"

omnictl get clusters
```

**Command line:**

```bash
omnictl --omni-url https://omni.your-tailnet.ts.net \
        --service-account-key "your-key-here" \
        get clusters
```

**In commands:**

```bash
# Check for existing key or prompt
if [ -z "$OMNICTL_SERVICE_ACCOUNT_KEY" ]; then
  echo "Set OMNICTL_SERVICE_ACCOUNT_KEY environment variable"
  exit 1
fi
```

### Key Permissions

| Role | Capabilities |
|------|--------------|
| Admin | Full access (create/delete clusters, manage users) |
| Operator | Manage clusters (create/scale/delete) |
| Reader | View-only access |

## Option 2: OIDC Browser Flow (Interactive)

For interactive use, omnictl can authenticate via browser.

### Login

```bash
omnictl --omni-url https://omni.your-tailnet.ts.net login
```

This opens a browser window for Tailscale OIDC authentication. After login, credentials are cached locally.

### Cached Credentials

Credentials are stored in `~/.config/omnictl/` and persist across sessions until they expire.

### Logout

```bash
omnictl logout
```

## Configuration File

Create `~/.config/omnictl/config.yaml` for persistent settings:

```yaml
contexts:
  default:
    url: https://omni.your-tailnet.ts.net
    # Optional: include service account key
    # serviceAccountKey: "your-key"

current-context: default
```

## Verifying Authentication

Test that authentication works:

```bash
# Should return cluster list (empty is OK)
omnictl get clusters

# Check current user
omnictl auth whoami
```

## Troubleshooting

**"unauthorized" error:**

- Service account key is invalid or expired
- Key doesn't have required permissions
- OIDC session expired (re-run `omnictl login`)

**"connection refused" error:**

- Omni URL is incorrect
- Omni is not running
- Network connectivity issue (check Tailscale)

**"certificate error":**

- Omni uses self-signed cert
- Tailscale HTTPS certificates not configured
- Add `--insecure` flag (not recommended for production)

## Best Practices

1. Use service account keys for automation
2. Use OIDC flow for interactive sessions
3. Store keys in environment variables, not command history
4. Use minimal permissions for service accounts
5. Rotate service account keys periodically
