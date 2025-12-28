# Troubleshooting

## Network Connectivity

### Port 443 Appears Blocked But No Firewall Found

**Symptom:** Port 443 connectivity issues reported, but firewall checks show no
active firewall rules blocking traffic.

**Cause:** No service was actually listening on port 443. The port appeared
"blocked" because nothing was bound to it.

**Solution:** Verified with `sudo ss -tlnp | grep :443` that no service was listening.
The issue was not a firewall block but rather a missing/misconfigured service that
should have been listening on the port.

---

## Systemd Service Configuration

### Systemd Service File Syntax Errors - Missing '=' on Lines 12-15

**Symptom:** Journal logs showed repeated errors:

```text
/etc/systemd/system/tsidp.service:11: Ignoring unknown escape sequences: "\"
/etc/systemd/system/tsidp.service:12: Missing '=', ignoring line.
/etc/systemd/system/tsidp.service:13: Missing '=', ignoring line.
/etc/systemd/system/tsidp.service:14: Missing '=', ignoring line.
/etc/systemd/system/tsidp.service:15: Missing '=', ignoring line.
```

**Cause:** The `ExecStart` directive used line continuation with backslashes
(`\`) and trailing spaces, which systemd failed to parse correctly. Lines 12-15
were continuation lines that systemd interpreted as separate invalid directives.

**Solution:** Consolidated the multi-line `ExecStart` command into a single line:

```ini
ExecStart=/usr/local/bin/tsidp -dir /var/lib/tsidp -hostname idp -enable-sts -port 443
```

Then ran:

```bash
sudo systemctl daemon-reload
sudo systemctl restart tsidp
```

---

## Application Configuration

### tsidp Not Binding to Port 443 Despite Configuration

**Symptom:** After fixing systemd syntax errors, the tsidp service started
successfully but `ss -tlnp | grep :443` showed no listener on port 443.

**Cause:** The tsidp application (using tsnet/Tailscale) is designed to listen
only on the Tailscale network interface, not on public network interfaces. The
`-port 443` flag applies within the Tailscale network context.

**Solution:** This is expected behavior, not a bug. The service is accessible
at `https://idp.tailfb3ea.ts.net` within the Tailscale network. The service
listens on port 40604 for Tailscale control plane traffic. If public port 443
access is required, a reverse proxy (nginx, Caddy) would need to be configured
to forward traffic to the Tailscale endpoint.

---

## Diagnostic Commands Used

### Firewall Investigation

- `sudo iptables -L -n -v` - Check IPv4 firewall rules
- `sudo ip6tables -L -n -v` - Check IPv6 firewall rules
- `sudo systemctl status ufw` - Check UFW status
- `sudo systemctl status firewalld` - Check firewalld status
- `sudo nft list ruleset` - Check nftables rules

### Port Listening Verification

- `sudo ss -tlnp` - List all TCP listening ports
- `sudo ss -tlnp | grep :443` - Check specific port 443
- `sudo netstat -tlnp | grep :443` - Alternative port check (command not found on this system)

### Service Debugging

- `sudo journalctl -u tsidp -f` - Follow service logs in real-time
- `sudo journalctl -u tsidp -n 20 --no-pager` - View recent service logs
- `sudo systemctl status tsidp` - Check service status
- `cat /etc/systemd/system/tsidp.service` - Inspect service file

### Process Investigation

- `systemctl list-units --type=service --state=running` - List running services
