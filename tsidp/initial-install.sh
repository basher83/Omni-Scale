#!/bin/bash
# initial-install.sh - Install tsidp from scratch on a fresh VM
# Usage: sudo ./initial-install.sh <TS_AUTHKEY>

set -e

TSIDP_VERSION="${TSIDP_VERSION:-0.0.9}"
TSIDP_HOSTNAME="${TSIDP_HOSTNAME:-tsidp}"

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo $0 <TS_AUTHKEY>)"
    exit 1
fi

# Require auth key argument
if [ -z "$1" ]; then
    echo "Usage: $0 <TS_AUTHKEY>"
    echo ""
    echo "Get an auth key from: https://login.tailscale.com/admin/settings/keys"
    echo "  - Enable 'Reusable' if you want to rerun this script"
    echo "  - Tag appropriately (e.g., tag:idp)"
    exit 1
fi

TS_AUTHKEY="$1"

echo "==> Installing tsidp v${TSIDP_VERSION} with hostname '${TSIDP_HOSTNAME}'..."

# Download and install binary
echo "==> Downloading tsidp..."
cd /tmp
wget -q "https://github.com/tailscale/tsidp/releases/download/v${TSIDP_VERSION}/tsidp_${TSIDP_VERSION}_linux_amd64.tar.gz"
tar -xzf "tsidp_${TSIDP_VERSION}_linux_amd64.tar.gz"
mv tsidp /usr/local/bin/
chmod +x /usr/local/bin/tsidp
rm -f "tsidp_${TSIDP_VERSION}_linux_amd64.tar.gz"

echo "==> Creating data directory..."
mkdir -p /var/lib/tsidp
chmod 700 /var/lib/tsidp
chown root:root /var/lib/tsidp

echo "==> Creating environment file..."
cat > /etc/default/tsidp << EOF
# Required while tsidp is pre-1.0
TAILSCALE_USE_WIP_CODE=1

# Auth key for initial registration (remove after first successful start)
TS_AUTHKEY=${TS_AUTHKEY}

# Force re-login on first start
TSNET_FORCE_LOGIN=1
EOF
chmod 600 /etc/default/tsidp
chown root:root /etc/default/tsidp

echo "==> Creating systemd service..."
cat > /etc/systemd/system/tsidp.service << EOF
[Unit]
Description=Tailscale IdP Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/tsidp
EnvironmentFile=/etc/default/tsidp
ExecStart=/usr/local/bin/tsidp -dir /var/lib/tsidp -hostname ${TSIDP_HOSTNAME} -enable-sts -port 443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Enabling and starting tsidp..."
systemctl daemon-reload
systemctl enable tsidp
systemctl start tsidp

echo "==> Waiting for service to initialize..."
sleep 5

if systemctl is-active --quiet tsidp; then
    echo "✓ tsidp is running"
    echo ""
    systemctl status tsidp --no-pager
    echo ""
    echo "==> Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Access tsidp at: https://${TSIDP_HOSTNAME}.<your-tailnet>.ts.net"
    echo "  2. Configure ACL grants in Tailscale admin console"
    echo "  3. Clean up auth key from /etc/default/tsidp:"
    echo "     sudo sed -i '/^TS_AUTHKEY=/d' /etc/default/tsidp"
    echo "     sudo sed -i '/^TSNET_FORCE_LOGIN=/d' /etc/default/tsidp"
else
    echo "✗ tsidp failed to start"
    echo ""
    journalctl -u tsidp -n 30 --no-pager
    exit 1
fi
