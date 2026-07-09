# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Omni-Scale is a production-ready deployment kit for self-hosted Sidero Omni with
Tailscale authentication. It manages Talos Linux Kubernetes clusters through:

- Sidero Omni (K8s lifecycle management) running as a Docker Compose stack
- Sidero Proxmox infrastructure provider for automatic Talos VM provisioning

## Skills

- omni-proxmox: guidance for deploying and managing Talos Linux Kubernetes
  clusters via Sidero Omni with the Proxmox infrastructure provider.

## Desired State

Desired substrate state is represented by checked-in Omni artifacts:

- `clusters/` contains Omni cluster templates, including `clusters/talos-prod-01.yaml`
- `machine-classes/` contains Proxmox VM sizing and placement definitions
- `omni/compose.yml` defines the self-hosted Omni Hub stack
- `proxmox-provider/compose.yml` and `proxmox-provider/config.yaml.example` define the provider stack

When changing desired state, compare the requested architecture against those
files first, then update the relevant docs so commands and paths stay aligned.

Post-bootstrap platform state belongs in `../mothership-gitops`, not this repo.

## Templates

Templates in `.claude/templates/` define output structures for consistent formatting:

| Template | Purpose |
|----------|---------|
| `plan-template.md` | Deployment plan structure |

Commands reference templates via `@.claude/templates/template-name.md`

## State Tracking

- Deployment plans: `docs/plans/`
- Task status tracked in plan files, not separate system

## Critical Gotchas

| Issue | Cause |
|-------|-------|
| "Invalid JWT" on login | Missing `extraClaims: { "email_verified": true }` in Tailscale ACL grant |
| `docker compose down -v` | Deletes Tailscale state, causes hostname collisions - never use `-v` |
| GPG passphrase prompt | Omni GPG key must have NO passphrase |
| VMs fail to register / hostname conflicts | Upstream provider bug - use `:local-fix` tag, not `:latest` |
| VM migration breaks Talos | Don't migrate - destroys node state. CD/DVD blocks it anyway. Destroy/recreate instead. |

## Code Exploration

ALWAYS read and understand relevant files before proposing code edits. Do not
speculate about code you have not inspected. Be rigorous and persistent in
searching code for key facts.
