#!/bin/bash
# update-systemd.sh - Update tsidp to use EnvironmentFile and proper systemd config
# Run on an existing tsidp VM to apply refined configuration

set -e

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo $0)"
    exit 1
fi

echo "==> Creating environment file..."
cat > /etc/default/tsidp << 'EOF'
# Required while tsidp is pre-1.0
TAILSCALE_USE_WIP_CODE=1
EOF
chmod 600 /etc/default/tsidp
chown root:root /etc/default/tsidp

echo "==> Updating systemd service..."
cat > /etc/systemd/system/tsidp.service << 'EOF'
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
EOF

echo "==> Reloading systemd and restarting tsidp..."
systemctl daemon-reload
systemctl restart tsidp

echo "==> Verifying service status..."
sleep 2
if systemctl is-active --quiet tsidp; then
    echo "✓ tsidp is running"
    systemctl status tsidp --no-pager
else
    echo "✗ tsidp failed to start"
    journalctl -u tsidp -n 20 --no-pager
    exit 1
fi

echo ""
echo "==> Update complete. Verify OIDC still works at your Omni URL."
