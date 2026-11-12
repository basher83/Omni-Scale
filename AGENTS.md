# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Omni-Scale is a production-ready deployment kit for self-hosted Sidero Omni with
Tailscale authentication. It manages Talos Linux Kubernetes clusters through:

- Sidero Omni (K8s lifecycle management) running as a Docker Compose stack
- Sidero Proxmox infrastructure provider for automatic Talos VM provisioning

## Skills

Skills in `.agents/skills/` are the operational interface for this repo:
agents execute them, the human approves plans. Docs describe the system;
skills own the procedures.

- omni-talos: provider lifecycle, machine classes, CEL storage selectors,
  cluster creation (vendored from lunar-claude via skills-lock.json).
- omni-update-rollout: renovate triage, compatibility gating, and split
  Talos-then-Kubernetes cluster version rollouts.
- omni-upgrade: upgrading the Omni Hub itself (release-note gating, deploy,
  verification).

Keep local pointers to a skill's supporting instructions, references, and scripts
within that skill's own directory. Do not reach into a sibling skill's resource
tree or assume a harness-specific plugin root. The broader review of skill
responsibilities, composition, and cross-harness loading is queued separately;
this rule does not declare existing skills audited or portable.

## Desired State

Desired substrate state is represented by checked-in Omni artifacts:

- `clusters/` contains Omni cluster templates, including `clusters/talos-prod-01.yaml`
- `machine-classes/` contains Proxmox VM sizing and placement definitions
- `omni/compose.yml` defines the self-hosted Omni Hub stack
- `proxmox-provider/compose.yml` and `proxmox-provider/config.yaml.example` define the provider stack

When changing desired state, compare the requested architecture against those
files first, then update the relevant docs so commands and paths stay aligned.

Post-bootstrap platform state belongs in `../mothership-gitops`, not this repo.

## Deployed Topology

- Omni Hub runs on the `omni-host` VM. Reach it with `ssh ansible@omni-host` over Tailscale; its stack lives in `~/docker/omni`.
- The Proxmox provider runs in the `omni-provider` LXC (CT 200) on Foxtrot, not on omni-host. Reach it with `tailscale ssh root@foxtrot`, then `pct exec 200 -- …`. The omni-talos skill's `provider-ctl.py` wraps this route.
- The deployed provider stack does not match `proxmox-provider/compose.yml`. The checked-in file names `:local-fix` and container `proxmox-provider`; the live stack runs upstream `:latest` under Compose project `omni-provider` (verified 2026-11-06). Reconcile the checked-in file to a pinned upstream release before redeploying from it. Unused historical images (`local-fix`, `84a37c0-dirty`, `fix-node`) remain in CT 200.

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
| Provider hostname workaround | Historical `:local-fix` guidance is superseded; establish the deployed digest and upstream fix ancestry using `.agents/skills/omni-talos/references/provider-setup.md` before selecting an image. |
| VM migration breaks Talos | Don't migrate - destroys node state. CD/DVD blocks it anyway. Destroy/recreate instead. |

## Code Exploration

ALWAYS read and understand relevant files before proposing code edits. Do not
speculate about code you have not inspected. Be rigorous and persistent in
searching code for key facts.

<!-- OPENWIKI:START -->

## OpenWiki

This repository has a generated `openwiki/` evidence index. It is optional just-in-time context, not required startup reading.

- Do not enumerate, preload, or search wikis at task start. Use retrieval when the user asks for it, when unfamiliar architecture or dependency behavior materially affects the task, or when source inspection leaves an important uncertainty. Stop once the question is grounded.
- When those conditions apply and OpenWiki retrieval tools are available, use `openwiki_search` for just-in-time context and `openwiki_read` for the relevant complete sections. If search returns `workspace_required`, ask which listed workspace to use and retry with its ID.
- Use `openwiki_list_workspaces` or `openwiki_list_wikis` when workspace membership itself needs to be discovered.
- If the retrieval tools are unavailable, read `openwiki/quickstart.md` and follow its links to the relevant pages.
- Treat source code and tests as authoritative. A brief's unknowns and review items are verification gaps, not automatic requirements.
- Prefer the narrowest quiet validation that proves the changed behavior. Preserve complete failure output.

Use the repository's documented maintenance process to refresh generated pages after source changes. Check its configuration and completed runs before relying on automatic updates. Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate.

<!-- OPENWIKI:END -->
