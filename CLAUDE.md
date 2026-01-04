# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Omni-Scale is a production-ready deployment kit for self-hosted Sidero Omni with Tailscale authentication. It manages Talos Linux Kubernetes clusters through:

- Sidero Omni (K8s lifecycle management) running as a Docker Compose stack
- Sidero Proxmox infrastructure provider for automatic Talos VM provisioning

## Skills

- omni-proxmox: This skill provides guidance for deploying and managing Talos Linux Kubernetes clusters via Sidero Omni with the Proxmox infrastructure provider.

## Specs

Specs in `specs/*.yaml` define desired state. When working with specs:

1. Parse spec to understand target architecture
2. Compare against current repo state
3. Identify gaps (what exists vs what's needed)
4. Generate prioritized task list

See @specs/README.md for schema documentation.

## Templates

Templates in `.claude/templates/` define output structures for consistent formatting:

| Template | Purpose |
|----------|---------|
| `plan-template.md` | Deployment plan structure |

Commands reference templates via `@.claude/templates/template-name.md`

## State Tracking

- Deployment plans: `docs/plans/`
- Task status tracked in plan files, not separate system
- Specs may include `status` block for component-level tracking

## Critical Gotchas

| Issue | Cause |
|-------|-------|
| "Invalid JWT" on login | Missing `extraClaims: { "email_verified": true }` in Tailscale ACL grant |
| `docker compose down -v` | Deletes Tailscale state, causes hostname collisions - never use `-v` |
| GPG passphrase prompt | Omni GPG key must have NO passphrase |
| VMs fail to register / hostname conflicts | Upstream provider bug - use `:local-fix` tag, not `:latest` |
| VM migration breaks Talos | Don't migrate - destroys node state. CD/DVD blocks it anyway. Destroy/recreate instead. |

## Code Exploration

ALWAYS read and understand relevant files before proposing code edits. Do not speculate about code you have not inspected. Be rigorous and persistent in searching code for key facts.
