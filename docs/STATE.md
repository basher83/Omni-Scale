# Omni-Scale State Assessment

Generated: 2025-12-29
Commit: 943f5c3

--- ---

  Infrastructure Status

  | Component         | Host                                    | Status      | Evidence                                                                                                                |
  |-------------------|-----------------------------------------|-------------|-------------------------------------------------------------------------------------------------------------------------|
  | Auth0 OIDC        | Managed service                         | Operational | Replaced tsidp for simpler operations                                                                                   |
  | Omni              | Holly (Quantum) - omni.spaceships.work  | Operational | DNS resolution fixed (kernel-mode sidecar), SQLite path configured, TUN device configured, startup race condition fixed |
  | Proxmox Provider  | Docker on Omni VM                       | Operational | Service account key configured, resource ID mismatch fixed (--id=Proxmox)                                               |
  | Tailscale Sidecar | Docker on Omni VM                       | Operational | Kernel mode configured, healthcheck with DNS verification                                                               |
  | Target Cluster    | Matrix (Foxtrot/Golf/Hotel)             | Ready       | Provider configured with Proxmox API endpoint; no Talos VMs deployed yet                                                |

  Open Infrastructure Issues

1. Unknown CEL Field for Storage Type Filtering — Cannot filter by storage type (rbd, lvmthin, zfspool). Workaround: use name field only. See TROUBLESHOOTING.md: "Unknown CEL Field for Storage Type Filtering"

  Contradiction Found

  DEPLOYMENT.md line 79 shows storageSelector: 'storage.filter(s, s.type == "rbd" ...)' — this CEL expression is invalid. type is a reserved CEL keyword. The documented MachineClass example will not work as written.

--- ---

  Plugin Implementation Status

  Commands

  | Command              | In PLAN.md | Implemented | Content Matches Spec | Notes                                                  |
  |----------------------|------------|-------------|----------------------|--------------------------------------------------------|
  | /provider-setup      | ✓          | ✓           | ✓                    | Added Edit tool; correct flat structure                |
  | /provider-verify     | ✓          | ✗           | —                    | Missing                                                |
  | /provider-status     | ✓          | ✓           | ✓                    | Added Edit tool                                        |
  | /machineclass-create | ✓          | ✓           | ✓                    | Added AskUserQuestion; includes omnictl download logic |
  | /machineclass-apply  | ✓          | ✗           | —                    | Missing                                                |
  | /cluster-create      | ✓          | ✗           | —                    | Missing                                                |
  | /cluster-status      | ✓          | ✓           | ✓                    | Added Edit tool                                        |

  Coverage: 4 of 7 commands (57%)

  Skills

  | Component   | Status   | Content                                                                                                               |
  |-------------|----------|-----------------------------------------------------------------------------------------------------------------------|
  | SKILL.md    | Complete | 294 lines; architecture, provider config, MachineClass, CEL, omnictl, workflows                                       |
  | references/ | 4 files  | cel-storage-selectors.md (108), proxmox-permissions.md (126), troubleshooting.md (227), omnictl-auth.md (128)         |
  | examples/   | 3 files  | machineclass-ceph.yaml, machineclass-local.yaml, cluster-template.yaml (enhanced with system extensions, GPU workers) |

  Coverage: 8 of 8 skill components (100%)

  Gap Resolution Status

  | Gap                      | Answer                 | Implemented | Evidence                                                                  |
  |--------------------------|------------------------|-------------|---------------------------------------------------------------------------|
  | GAP-01 (manifest)        | plugin.json fields     | ✓           | Matches spec + adds repository, license, keywords                         |
  | GAP-03 (naming)          | Flat command files     | ✓           | commands/provider-setup.md not commands/provider/setup.md                 |
  | GAP-07 (docker path)     | Use -f flag            | ✓           | All docker compose calls use -f ${CLAUDE_PROJECT_DIR}/docker/compose.yaml |
  | GAP-08 (omnictl)         | Download on first use  | ✓           | machineclass-create.md lines 98-112                                       |
  | GAP-12 (machine-classes) | Directory at repo root | ✓           | /machine-classes/ exists with matrix-worker.yaml, README.md               |
  | GAP-09 (hooks)           | Defer to v2            | ✓ Deferred  | Per documented decision                                                   |
  | GAP-10 (agents)          | Defer to v2            | ✓ Deferred  | Per documented decision                                                   |

--- ---

  Locked-In Decisions

  Architecture (deployed — change requires redeployment)

  | Decision                        | Evidence                                             | Change Cost                                |
  |---------------------------------|------------------------------------------------------|--------------------------------------------|
  | tsidp and Omni on separate VMs  | CLAUDE.md, DEPLOYMENT.md — tsnet/Tailscale conflicts | Critical — requires VM reprovision         |
  | Tailscale-only access           | compose.yaml Serve config, no public IPs             | High — rewrites service configs, DNS, auth |
  | Proxmox cluster target (Matrix) | 192.168.3.5:8006 (LAN, provider L2-adjacent)         | High — new credentials, storage validation |
  | CEPH RBD storage (vm_ssd)       | DEPLOYMENT.md — 12TB pool, replication factor 3      | Medium — MachineClass rewrites             |

  Configuration (baked into services)

  | Setting        | Value                                     | File                             |
  |----------------|-------------------------------------------|----------------------------------|
  | Service names  | omni-tailscale, omni, proxmox-provider    | docker/compose.yaml              |
  | Network mode   | service:omni-tailscale (shared namespace) | docker/compose.yaml              |
  | Tailscale mode | Kernel (TS_USERSPACE=false)               | docker/compose.yaml              |
  | Provider ID    | Proxmox (capital P)                       | docker/compose.yaml --id=Proxmox |
  | Serve ports    | 443, 8090, 8100                           | docker/compose.yaml              |

  Constraints (learned from failures)

  | Constraint                                 | Reason                                           |
  |--------------------------------------------|--------------------------------------------------|
  | Never use docker compose down -v           | Deletes Tailscale state → hostname collisions    |
  | Tailscale sidecar requires kernel mode     | Userspace breaks MagicDNS resolution             |
  | Healthcheck must verify DNS                | Just /healthz is insufficient; need getent hosts |
  | GPG key must have NO passphrase            | Omni can't unlock key at startup otherwise       |
  | Storage selector cannot filter by type     | Reserved CEL keyword — use name only             |
  | Initial user email must match OIDC exactly | No normalization; case-sensitive                 |

--- ---

  Flexible Decisions

- Plugin command names: Standalone .md files, not referenced by infrastructure
- Skill content: Pure documentation; deployment doesn't depend on it
- MachineClass specs: Not yet deployed; CPU/memory/disk easily changed
- Cluster templates: Examples only; actual clusters are separate definitions
- Proxmox auth strategy: root+password is testing; can upgrade to API tokens without redeployment
- Tailscale ACLs: Managed in admin console, takes effect immediately

--- ---

  Project Progress

  PLAN.md Acceptance Criteria

  | Criteria                                  | Status | Evidence                                                                |
  |-------------------------------------------|--------|-------------------------------------------------------------------------|
  | Plugin loads without errors               | ✓      | plugin.json valid, commands discoverable                                |
  | /provider-setup works                     | ✓      | Command implemented with full workflow                                  |
  | /provider-verify confirms connectivity    | ✗      | Command not implemented                                                 |
  | /machineclass-create generates valid YAML | ✓      | Command implemented with interactive prompts                            |
  | /machineclass-apply applies to Omni       | ✗      | Command not implemented                                                 |
  | /cluster-create provisions VMs            | ✗      | Command not implemented                                                 |
  | State persists across sessions            | ✓      | .claude/omni-scale.local.md.example present, commands read/update state |
  | Skills provide troubleshooting context    | ✓      | 589 lines across 4 reference files                                      |

--- ---

  Actionable Summary

  Working:

- All infrastructure components operational (tsidp, Omni, Proxmox Provider, Tailscale networking)
- 4 core plugin commands implemented (/provider-setup, /provider-status, /machineclass-create, /cluster-status)
- Complete skill documentation with references and examples
- State management pattern established
- 12 of 14 implementation gaps resolved

  Missing:
- /provider-verify command
- /machineclass-apply command
- /cluster-create command
- No Talos VMs deployed yet (provider ready, no clusters created)

  Blocked:
- CEL storage type filtering — cannot use type == "rbd" (reserved keyword). Blocks multi-storage-type configurations. Workaround: filter by name only.
