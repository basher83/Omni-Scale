# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Omni-Scale is a production-ready deployment kit for self-hosted Sidero Omni with Tailscale authentication. It manages Talos Linux Kubernetes clusters through:

- tsidp (Tailscale OIDC identity provider) running as a systemd service
- Omni (K8s lifecycle management) running as a Docker Compose stack
- Proxmox infrastructure provider for automatic Talos VM provisioning

All components communicate exclusively through Tailscale encrypted tunnels.

## Development Commands

```bash
# Tool management (mise auto-installs tools)
mise install                          # Install all configured tools

# Pre-commit hooks
mise run hooks-install                # Install prek and infisical hooks
mise run pre-commit-run               # Run all pre-commit hooks

# Changelog (conventional commits)
mise run changelog                    # Update CHANGELOG.md with unreleased changes
mise run changelog-bump 0.1.0         # Tag and update changelog for release

# Markdown linting
mise run markdown-lint                # Check markdown files
mise run markdown-fix                 # Auto-fix markdown files

# Secret scanning
mise run infisical-scan               # Scan for leaked secrets

# Docker operations (from docker/ directory)
docker compose up -d                  # Start Omni stack
docker compose logs -f omni           # Follow Omni logs
docker compose logs -f proxmox-provider  # Follow provider logs
docker compose ps                     # Service status
```

## Architecture

```text
tsidp VM (Debian)           Omni VM (Ubuntu + Docker)
┌─────────────────┐         ┌─────────────────────────────────┐
│   tsidp binary  │◀────────│  omni-tailscale (sidecar)       │
│   (systemd)     │  OIDC   │  omni (K8s management)          │
└─────────────────┘         │  proxmox-provider               │
                            └──────────────┬──────────────────┘
                                           │ Proxmox API
                                           ▼
                            ┌─────────────────────────────────┐
                            │     Proxmox Cluster             │
                            │     (Talos VMs)                 │
                            └─────────────────────────────────┘
```

Key design constraint: tsidp and Omni must run on separate hosts due to networking conflicts between tsnet and host Tailscale.

## Repository Structure

- `tsidp/` - Tailscale OIDC provider installation scripts (bash, systemd)
- `docker/` - Omni + Proxmox provider Docker Compose stack
- `docs/` - Supplemental guides (GPG key setup)
- `PLAN.md` - Claude Code plugin architecture for future development

## Conventions

**Commits:** Conventional Commits format with optional scopes
- `feat(docker):`, `fix(tsidp):`, `docs:`, `chore:`

**Shell scripts:** Use `set -e` for error handling, include root checks and argument validation

**YAML configs:** Comment "why" not "what", use environment variable interpolation

## Critical Gotchas

| Issue | Cause |
|-------|-------|
| tsidp and Omni on same host | Networking conflicts between tsnet and host Tailscale |
| "Invalid JWT" on login | Missing `extraClaims: { "email_verified": true }` in Tailscale ACL grant |
| `docker compose down -v` | Deletes Tailscale state, causes hostname collisions - never use `-v` |
| GPG passphrase prompt | Omni GPG key must have NO passphrase |

## Plugin Development

PLAN.md describes a planned `omni-scale` Claude Code plugin with commands for provider setup, machine class creation, and cluster management. When implementing:

- Commands reference skills for deep knowledge
- State tracked in `.claude/omni-scale.local.md`
- Skills contain CEL storage selector references and troubleshooting
