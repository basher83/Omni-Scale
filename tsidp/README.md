# TSIDP - Binary Installation Guide

## Overview

TSIDP (Tailscale Identity Provider) is an OIDC/OAuth server that runs on your
Tailscale network, allowing you to use Tailscale identities to authenticate into
applications. This guide covers the **native binary installation** managed by
systemd (not Docker).

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    Your Tailscale Network                    │
│                                                              │
│  ┌──────────────┐         ┌─────────────────────────────┐  │
│  │   Clients    │────────▶│  TSIDP Server (this VM)     │  │
│  │ (browsers,   │  HTTPS  │  • Listens on Tailscale IP  │  │
│  │  apps, MCP)  │         │  • Port 443 (Tailscale net) │  │
│  └──────────────┘         │  • Hostname: tsidp          │  │
│                           │  • URL: https://tsidp.      │  │
│                           │    yourtailnet.ts.net       │  │
│                           └─────────────────────────────┘  │
│                                      │                      │
│                                      │ Validates users      │
│                                      ▼                      │
│                           ┌─────────────────────────────┐  │
│                           │  Tailscale Control Plane    │  │
│                           │  (coordination service)     │  │
│                           └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

Local Storage: /var/lib/tsidp/
├── tailscaled.state       # Tailscale connection state
├── oidc-key.json          # Signing keys for tokens
├── oidc-funnel-clients.json  # Registered OAuth clients
└── certs/                 # TLS certificates (auto-generated)
```

### How It Works

1. **tsidp** uses **tsnet** (embedded Tailscale library) to join your Tailscale network
2. It doesn't bind to public network interfaces - only accessible via Tailscale
3. Tailscale handles TLS certificate generation automatically (via Let's Encrypt)
4. Authentication is validated against your Tailscale network's user list
5. Port 443 traffic stays within the Tailscale network (encrypted WireGuard tunnel)

## Prerequisites

### Required

- **Tailscale account** with admin access
- **Tailscale auth key** from <https://login.tailscale.com/admin/settings/keys>
  - Must be created with appropriate [tags](https://tailscale.com/kb/1068/tags)
  - Recommended: Create a dedicated tag like `tag:idp` for this service
- **Linux server** with systemd (tested on Debian)
- **Root or sudo access** for installation

### Recommended Knowledge

- Basic systemd concepts (services, restart behavior)
- Understanding of OAuth/OIDC flows (if integrating with apps)
- Tailscale network basics (MagicDNS, HTTPS)

## Helper Scripts

This directory includes automation scripts for common operations:

| Script | Purpose |
|--------|--------|
| `initial-install.sh` | Fresh install on a new VM |
| `update-systemd.sh` | Update existing install to current config |

```bash
# Fresh install
sudo ./initial-install.sh tskey-auth-XXXXX

# Update existing installation
sudo ./update-systemd.sh
```

The manual steps below document what these scripts automate.

## Quick Start (Manual)

### 1. Download and Install Binary

```bash
# Download the latest release (or specific version)
wget https://github.com/tailscale/tsidp/releases/download/v0.0.9/tsidp_0.0.9_linux_amd64.tar.gz

# Extract
tar -xzf tsidp_0.0.9_linux_amd64.tar.gz

# Install binary
sudo cp tsidp /usr/local/bin/
sudo chmod +x /usr/local/bin/tsidp
```

### 2. Create Data Directory

```bash
# Create directory for persistent state
sudo mkdir -p /var/lib/tsidp

# Set permissions (tsidp runs as root in our setup)
sudo chmod 700 /var/lib/tsidp
```

### 3. Create Environment File

Create `/etc/default/tsidp` with secure permissions:

```bash
sudo touch /etc/default/tsidp
sudo chmod 600 /etc/default/tsidp
```

Add the following content:

```bash
# Required while tsidp is pre-1.0
TAILSCALE_USE_WIP_CODE=1

# Auth key for initial registration (can remove after first successful start)
TS_AUTHKEY=tskey-auth-YOUR_KEY_HERE

# Force re-login (useful during setup, remove for production)
TSNET_FORCE_LOGIN=1
```

**Replace `YOUR_KEY_HERE` with your actual Tailscale auth key.**

### 4. Create Systemd Service

Create `/etc/systemd/system/tsidp.service`:

```ini
[Unit]
Description=Tailscale IdP Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/tsidp
EnvironmentFile=/etc/default/tsidp
ExecStart=/usr/local/bin/tsidp -dir /var/lib/tsidp -hostname tsidp -enable-sts -port 443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 5. Start the Service

```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable tsidp

# Start the service
sudo systemctl start tsidp

# Check status
sudo systemctl status tsidp
```

### 6. Verify It's Running

```bash
# Check logs for successful startup
sudo journalctl -u tsidp -n 50 --no-pager

# Look for this line:
# INFO tsidp server started server_url=https://tsidp.yourtailnet.ts.net
```

Visit `https://tsidp.yourtailnet.ts.net` in a browser (while connected to Tailscale).

## Configuration

### Systemd Service File (`/etc/systemd/system/tsidp.service`)

#### `After=network-online.target` + `Wants=network-online.target`

- **What it does:** Waits for network to be fully online (not just interfaces configured)
- **Why:** tsidp needs to reach Tailscale coordination servers on startup
- **What breaks:** With just `network.target`, service can start before DHCP/routes are ready

#### `User=root`

- **What it does:** Runs tsidp as the root user
- **Why:** tsidp needs to write to `/var/lib/tsidp` and bind to port 443 (privileged port)
- **Security note:** Consider creating a dedicated user with appropriate capabilities in production

#### `WorkingDirectory=/var/lib/tsidp`

- **What it does:** Sets the working directory for the process
- **Why:** Ensures any relative paths resolve correctly

#### `EnvironmentFile=/etc/default/tsidp`

- **What it does:** Loads environment variables from a separate file
- **Why:** Keeps secrets out of the unit file (visible in `systemctl show` and logs)
- **Security:** The file should be `chmod 600` owned by root

#### Environment Variables (in `/etc/default/tsidp`)

| Variable | Required | Purpose |
|----------|----------|--------|
| `TAILSCALE_USE_WIP_CODE=1` | Yes | Enables experimental features (required while tsidp < v1.0) |
| `TS_AUTHKEY` | First run only | Authenticates node to tailnet. Can be removed after initial registration. |
| `TSNET_FORCE_LOGIN=1` | No | Forces re-auth on restart. Remove for production. |

#### `ExecStart` Command Breakdown

```bash
/usr/local/bin/tsidp \
  -dir /var/lib/tsidp \      # Persistent state storage
  -hostname tsidp \           # Becomes tsidp.yourtailnet.ts.net
  -enable-sts \               # Enable OAuth token exchange (RFC 8693)
  -port 443                   # Port for HTTPS (on Tailscale network)
```

**Important:** This must be a single line (no backslashes). Systemd doesn't handle line continuation well.

##### `-dir /var/lib/tsidp`

- **What it does:** Stores Tailscale state, OIDC keys, and client registrations
- **What breaks:** If directory doesn't exist or lacks permissions, service fails silently
- **Data stored:**
  - `tailscaled.state` - Connection state
  - `oidc-key.json` - Token signing keys (sensitive!)
  - `oidc-funnel-clients.json` - OAuth client registrations
  - `certs/` - TLS certificates

##### `-hostname tsidp`

- **What it does:** Sets the MagicDNS hostname on your Tailscale network
- **Result:** Service accessible at `https://tsidp.yourtailnet.ts.net`
- **What breaks:** Changing this creates a NEW Tailscale node; old hostname won't work

##### `-enable-sts`

- **What it does:** Enables Secure Token Service for OAuth token exchange
- **Why:** Required for MCP (Model Context Protocol) integrations
- **What breaks:** MCP clients can't authenticate without this

##### `-port 443`

- **What it does:** Listens on port 443 **within the Tailscale network**
- **Why:** Standard HTTPS port expected by OAuth/OIDC clients
- **Common confusion:** This does NOT bind to public port 443 - only Tailscale network

#### `Restart=always` and `RestartSec=5`

- **What it does:** Automatically restarts service if it crashes
- **Why:** Ensures high availability
- **Behavior:** Waits 5 seconds between restart attempts

### Application Capability Grants

**Critical:** By default, tsidp **denies all access** to admin UI and client registration.

You must configure grants in your Tailscale ACL policy at:
<https://login.tailscale.com/admin/acls/>

Example minimal grant:

```hujson
"grants": [
  {
    "src": ["autogroup:admin"],  // Only Tailscale admins
    "dst": ["tag:idp"],           // Your tsidp node tag
    "app": {
      "tailscale.com/cap/tsidp": [
        {
          "allow_admin_ui": true,    // Access admin interface
          "allow_dcr": true,          // Dynamic client registration
          "users": ["*"],             // All users can authenticate
          "resources": ["*"]          // All resources accessible
        }
      ]
    }
  }
]
```

**What breaks:** Without this grant, you'll get 403 Forbidden errors when accessing the admin UI.

## Gotchas

### Port 443 Not Listening on Public Interface

- **Symptom:** `ss -tlnp | grep :443` shows nothing
- **Why:** tsidp binds to Tailscale interface only, not public/eth0
- **Fix:** This is expected! Access via `https://tsidp.yourtailnet.ts.net` (Tailscale network)

### Service Starts But Can't Access Web UI

- **Symptom:** Service running, logs look good, but web browser shows error
- **Causes:**
  1. TLS certificate still generating (wait 2-5 minutes after first start)
  2. Not connected to Tailscale network on client device
  3. MagicDNS not enabled in Tailscale settings
  4. Application capability grant missing (403 Forbidden)
- **Fix:** Check logs: `sudo journalctl -u tsidp -f`

### "Missing '=' Ignoring Line" Errors

- **Symptom:** Systemd logs show syntax errors about missing equals signs
- **Cause:** Multi-line `ExecStart` with backslashes (systemd parsing issue)
- **Fix:** Put entire ExecStart command on single line (see Configuration section)

### Changing Hostname Creates New Node

- **Symptom:** After changing `-hostname`, old URL doesn't work
- **Why:** Each hostname creates a separate Tailscale node
- **Fix:** Delete old node from Tailscale admin console, or keep using original hostname

### Auth Key Expires

- **Symptom:** Service fails to start with "unable to validate API key" error
- **Cause:** Tailscale auth keys expire (default 90 days)
- **Fix:**
  1. Generate new auth key in Tailscale admin console
  2. Update `TS_AUTHKEY` in service file
  3. Run: `sudo systemctl daemon-reload && sudo systemctl restart tsidp`

### State Directory Permissions

- **Symptom:** Service starts but immediately crashes
- **Cause:** `/var/lib/tsidp` doesn't exist or has wrong permissions
- **Fix:**

  ```bash
  sudo mkdir -p /var/lib/tsidp
  sudo chmod 700 /var/lib/tsidp
  sudo chown root:root /var/lib/tsidp
  ```

### Complete State Reset

- **Symptom:** Need to re-register node or hostname is suffixed (tsidp-1, tsidp-2)
- **Cause:** Old state conflicts with new registration
- **Fix:**

  ```bash
  sudo systemctl stop tsidp
  sudo rm -rf /var/lib/tsidp/*
  # Also remove old device from Tailscale admin console
  sudo systemctl start tsidp
  ```

### Can't Register OAuth Clients

- **Symptom:** Dynamic client registration fails
- **Cause:** Missing capability grant for `allow_dcr`
- **Fix:** Add capability grant in Tailscale ACL (see Configuration section)

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for detailed troubleshooting procedures including:

- Firewall investigation steps
- Systemd service debugging
- Port listening verification
- Common error messages and solutions

### Quick Debug Commands

```bash
# Check service status
sudo systemctl status tsidp

# View recent logs
sudo journalctl -u tsidp -n 50 --no-pager

# Follow logs in real-time
sudo journalctl -u tsidp -f

# Check what ports are listening
sudo ss -tlnp

# Verify tsidp binary
/usr/local/bin/tsidp -help

# Check Tailscale connectivity from tsidp perspective
sudo ls -la /var/lib/tsidp/
```

## Updating tsidp

```bash
# Stop service
sudo systemctl stop tsidp

# Download new version
wget https://github.com/tailscale/tsidp/releases/download/vX.X.X/tsidp_X.X.X_linux_amd64.tar.gz

# Extract and replace binary
tar -xzf tsidp_X.X.X_linux_amd64.tar.gz
sudo cp tsidp /usr/local/bin/
sudo chmod +x /usr/local/bin/tsidp

# Start service
sudo systemctl start tsidp

# Verify
sudo systemctl status tsidp
```

**Note:** State in `/var/lib/tsidp` is preserved across updates.

## Uninstalling

```bash
# Stop and disable service
sudo systemctl stop tsidp
sudo systemctl disable tsidp

# Remove service file
sudo rm /etc/systemd/system/tsidp.service
sudo systemctl daemon-reload

# Remove binary
sudo rm /usr/local/bin/tsidp

# Remove data (CAUTION: This deletes OAuth clients and keys)
sudo rm -rf /var/lib/tsidp

# Remove node from Tailscale admin console
# Visit: https://login.tailscale.com/admin/machines
```

## Integration Examples

### Using with MCP (Model Context Protocol)

tsidp supports full MCP authorization including Dynamic Client Registration (DCR). See upstream examples:

- [Basic MCP Client/Server](https://github.com/tailscale/tsidp/tree/main/examples/mcp-server)
- [MCP Gateway](https://github.com/tailscale/tsidp/tree/main/examples/mcp-gateway)

### Using with Web Applications

Any application supporting custom OIDC providers can use tsidp:

**Discovery URL:** `https://tsidp.yourtailnet.ts.net/.well-known/openid-configuration`

**Typical settings:**

- **Issuer:** `https://tsidp.yourtailnet.ts.net`
- **Client ID:** Register via admin UI or DCR
- **Client Secret:** Provided during registration
- **Scopes:** `openid profile email`

See upstream docs for specific applications:

- [Proxmox integration](https://github.com/tailscale/tsidp/tree/main/docs/proxmox)

## Security Considerations

1. **Auth Key Storage:** The systemd service file contains your Tailscale auth key

   ```bash
   sudo chmod 600 /etc/systemd/system/tsidp.service
   ```

2. **State Directory:** Contains sensitive signing keys

   ```bash
   sudo chmod 700 /var/lib/tsidp
   ```

3. **Network Isolation:** tsidp is only accessible via Tailscale network by design

4. **Capability Grants:** Be restrictive with `allow_dcr` and admin UI access

5. **Funnel Mode:** Do NOT enable `-funnel` unless you need public internet access (exposes to internet)

## Support

- **Upstream Project:** <https://github.com/tailscale/tsidp>
- **Tailscale Docs:** <https://tailscale.com/kb>
- **Community Project:** File issues on GitHub

## License

MIT
