# TODO

Future enhancements and ideas. Captured here to stay focused on current work.

## Proxmox + Tailscale Integration

### tsidp for PVE Login
- Configure Proxmox to use tsidp as OIDC provider
- Login to Proxmox UI with Tailscale identity
- Reference: https://github.com/tailscale/tsidp/tree/main/docs/proxmox

### Tailscale Serve for Proxmox API
- Install Tailscale on Matrix nodes (start with Foxtrot)
- `tailscale serve 8006` to expose Proxmox API via Tailscale
- Note: Provider now uses LAN IP (192.168.3.5:8006) since it's L2-adjacent on Foxtrot LXC
- Still useful for remote Proxmox UI access with auto-renewed HTTPS certs

### Tailscale HTTPS Certs for Proxmox UI
- Use `tailscale cert` to get Let's Encrypt certs
- Configure Proxmox to use Tailscale-issued certs
- Reference: Homelab_SSL_Certificate_Reference.md (Pattern 2: Tailscale Serve)

## Infrastructure Provider

### ~~Production Proxmox Auth~~ (Done)
- ~~Create dedicated user~~ → Using `terraform@pam!automation`
- ~~Create API token with limited permissions~~ → Token configured
- ~~Update config.yaml to use token auth~~ → Provider deployed on Foxtrot LXC

## Documentation

### Claude Code Task Specs
- Set up hybrid workflow for task handoff
- Structure TBD based on Brent's solution

---

*Keep this list short. Move completed items to a CHANGELOG or delete them.*
