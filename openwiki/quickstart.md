---
type: orientation
title: Quickstart and engineering task map
description: Safe local setup and task-based routes for the Omni-managed Talos substrate, separating offline validation, authenticated inspection, and infrastructure changes.
tags: [quickstart, substrate, mise, validation, operations]
verified:
  - by: openwiki/0.9.0
    at: 2026-11-13T15:52:19.245Z
sources:
  - id: openwiki-source-164e2da859b5277df81c7d94
    resource: repo://.github/workflows/ci.yml
  - id: openwiki-source-6d4b4e707b8d60b6ccfa3425
    resource: repo://.github/workflows/openwiki-update.yml
  - id: openwiki-source-4d1645cb6317345817452838
    resource: repo://.pre-commit-config.yaml
  - id: openwiki-source-8037e2358a2c4f9b2c722a11
    resource: repo://AGENTS.md
  - id: openwiki-source-d3cba2290d494077f7f1ce41
    resource: repo://clusters/README.md
  - id: openwiki-source-b7b85158fefb9a43f4887ead
    resource: repo://docs/OPERATIONS.md
  - id: openwiki-source-56977d6cc5e62805a883aac6
    resource: repo://machine-classes/README.md
  - id: openwiki-source-72b5d686f860ea86c8592080
    resource: repo://mise.toml
  - id: openwiki-source-b51bf659e7783ebdceecb0ff
    resource: repo://omni/compose.yml
  - id: openwiki-source-455c7f12dc1bc2d4498fc94c
    resource: repo://proxmox-provider/compose.yml
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
  - id: openwiki-source-41c698f171093946a252389b
    resource: repo://scripts/disaster-recovery.sh
  - id: openwiki-source-4c56c4085c56a3ab75df5178
    resource: repo://scripts/README.md
generated: { by: "openwiki/0.9.0", at: "2026-11-13T15:52:19.245Z" }
---

# Quickstart and engineering task map

## Know the boundary

Omni-Scale owns the self-hosted **Omni Hub**, **Proxmox infrastructure provider**, machine classes, cluster templates, Talos node requirements, and connectivity constraints through the GitOps handoff. Post-bootstrap platform applications and their operations belong to [mothership-gitops](https://github.com/basher83/mothership-gitops), not this repository.

Start with [substrate architecture and ownership](architecture/substrate.md) for the system model. The Hub manages clusters; the provider provisions Proxmox VMs. Administrative Tailscale access does **not** replace boot-time LAN connectivity: the provider must share the Talos VMs' L2 network, and boot-time DNS must resolve Omni to a reachable LAN address. See [network and identity dependencies](concepts/network-and-identity.md).

## Use context just in time

[AGENTS.md](../AGENTS.md#openwiki) treats the generated `openwiki/` evidence index as **optional just-in-time context**, not required startup reading. Do not enumerate, preload, or search the wiki at task start. Retrieve context when requested, when unfamiliar architecture or dependency behavior materially affects the task, or when source inspection leaves an important uncertainty; stop once the question is grounded.

When available, use `openwiki_search`, then `openwiki_read` for the relevant complete sections. If search returns `workspace_required`, ask which listed workspace to use and retry with its ID; use `openwiki_list_workspaces` or `openwiki_list_wikis` only when workspace membership needs discovery. Without retrieval tools, use this page's task routes below.

**Source code and tests remain authoritative.** Unknowns and review items in a brief are verification gaps, not automatic requirements. The operational skills in [`.agents/skills/`](../.agents/skills/) own procedures: agents execute them and humans approve plans; documentation describes the system. Prefer the narrowest quiet validation that proves the change, and preserve complete failure output.

## Set up locally, without touching infrastructure

From the repository root, with [mise](https://mise.jdx.dev/) installed:

```bash
mise install
mise tasks
mise run validate:omni
```

Review [mise.toml](../mise.toml) before trusting or executing repository configuration. It requires mise **2026.2.17** or newer, pins `omnictl` to **1.9.3** alongside the linting tools, and configures a local `.venv`. Tool installation can require network access; it is not a deployment step.

`validate:omni` validates both the production and test cluster templates **offline**, without Omni authentication. It does not prove that a provider, storage selector, network path, or running cluster works.

For the broader local/CI quality gate:

```bash
mise run check
```

This runs `pre-commit run --all-files`: syntax, shell, selected Markdown, workflow, secret-pattern, Renovate, and template checks. Some hooks can fix local files; review the resulting diff. First-time hook installation may need network access. See [validation and CI](testing/validation.md) for scope and limitations; these checks are not a live infrastructure test.

## Refresh generated documentation separately

After source changes, prefer updating source code/docs and regenerating rather than hand-editing generated pages unless explicitly asked. Follow [OpenWiki maintenance and partial-failure review](testing/validation.md#openwiki-maintenance-is-a-separate-pipeline): the [OpenWiki Update workflow](../.github/workflows/openwiki-update.yml) is configured for daily **08:00 UTC** runs or manual `workflow_dispatch`, attempting to create/update an `openwiki/update` PR. It is separate from ordinary CI and `mise run check`, and is not infrastructure validation.

Inspect the current workflow configuration, completed run outcome, failure output, and proposed diff before relying on an automatic refresh. A PR can preserve completed pages after a generation failure; its existence does **not** prove the update succeeded. The linked maintenance guide covers credentials, tailnet/model-service dependencies, and review of generated instructions and workflow changes.

## Inspect an existing environment separately

Only after obtaining an Omni configuration and completing sign-in using the [operations guide](../docs/OPERATIONS.md):

```bash
omnictl config contexts
omnictl get clusters
omnictl get machineclasses
omnictl get infraproviders
omnictl get machines
omnictl cluster template diff -f clusters/talos-prod-01.yaml
```

These inspect local contexts or remote state rather than apply changes. Confirm the intended context first. `omnictl get clusters` can open a browser for OIDC authentication and cache credentials locally. Template `diff` is a preview against the environment; do not confuse it with offline `validate` or mutating `sync`.

## Choose a task, then follow its runbook

| Task | Source entrypoint | Wiki route |
|---|---|---|
| Understand or change the Hub stack | [omni/compose.yml](../omni/compose.yml), [environment example](../omni/omni.env.example) | [Architecture](architecture/substrate.md); [Hub upgrades and persistent state](operations/hub-lifecycle.md) |
| Diagnose or change VM provisioning | [proxmox-provider/compose.yml](../proxmox-provider/compose.yml), [provider config example](../proxmox-provider/config.yaml.example) | [Troubleshooting and provider operations](operations/troubleshooting.md) |
| Change VM sizing, storage selection, or worker placement | [machine-classes/README.md](../machine-classes/README.md) | [Machine classes and safe cluster changes](workflows/cluster-changes.md) |
| Change Talos/Kubernetes versions, node counts, extensions, or patches | [clusters/README.md](../clusters/README.md), [production template](../clusters/talos-prod-01.yaml) | [Cluster changes](workflows/cluster-changes.md); [validation](testing/validation.md) |
| Understand CNI bootstrap and the platform boundary | [cluster substrate contract](../clusters/README.md#longhorn-substrate-contract) | [CNI bootstrap and GitOps handoff](integrations/gitops-handoff.md) |
| Review automation before running it | [scripts/README.md](../scripts/README.md), [recovery script](../scripts/disaster-recovery.sh) | [Disaster recovery and its limits](workflows/disaster-recovery.md) |
| Intentionally deploy a new environment | [deployment guide](../docs/DEPLOYMENT.md) | [Deploy the Hub and provider](workflows/deploy-substrate.md) |

## Stop before mutations

Deployment and disaster recovery are **not quickstart defaults**. `omnictl apply`, template `sync`/`delete`, Compose lifecycle changes, and recovery scripts belong to the linked workflows, with credentials, target context, and persistent state reviewed first.

Two especially important review gates:

- **Provider image:** the checked-in Compose file still references `:local-fix`, but its comments identify that as historical and require reconciliation with the verified deployed digest before redeployment. Do not copy the README's old hostname workaround as current deployment advice.
- **Recovery task:** `mise run disaster-recovery` invokes the script that destroys and recreates the target cluster; it is not a health check. It defaults to `talos-prod-01` and requires confirmation. Read the [recovery workflow](workflows/disaster-recovery.md) before considering it.
