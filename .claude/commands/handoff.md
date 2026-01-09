---
description: Produce a handoff brief for a fresh instance to continue work
---

# Session Handoff

Context is exhausted. Produce a handoff brief for a fresh instance to continue this work.

**Principle:** Report observations, not synthesis. Capture state not recoverable from repo or plan.

## Output Location

`.claude/handoff.local.md` (overwrite if exists)

## Context

Conversation contents:
@docs/gitops-boot-convo.txt

## Required Sections

### 1. Loop Position

Single line:

- **Phase**: Plan | Build | Review | Fix
- **Detail**: Task name/number, or what's being reviewed/fixed

Example: `Build — Task 3: Configure control plane endpoints`

### 2. External State Mutations

Actions taken outside the repo that a fresh instance can't see via `git diff`:

| What | Action Taken | Verified? |
|------|--------------|-----------|
| Talos control plane | `talosctl apply-config -n 10.0.1.10` | ❌ didn't confirm node joined |
| Kubernetes deployment | `kubectl apply -f deployment.yaml` | ❌ rollout status unknown |
| Terraform/OpenTofu | `tofu apply` in `infra/talos/` | ✅ apply completed |
| Omni cluster registration | registered via UI | ❌ didn't verify in dashboard |

**Include only mutations that occurred. Skip if none.**

Capture:

- Infrastructure provisioning (VMs, clusters, networks)
- Deployments and rollouts
- Configuration applied to remote systems
- API calls that changed state
- Manual actions in UIs/dashboards

### 3. Blockers Hit

Errors or unexpected behaviors. Raw observations, not root cause analysis:

```text
talosctl bootstrap failed: "etcd cluster not healthy"
Retried 3x with 30s intervals, same result
Workaround: manually waited 2min, succeeded on 4th attempt
```

Skip if none.

### 4. Resume Point

One imperative sentence:

```text
Resume: Verify control plane node joined cluster, then proceed to Task 4 (worker node join).
```

---

## What NOT to Include

- File changes (recoverable via `git diff`)
- Learnings or pattern extraction (defer to `/complete-plan`)
- Plan updates or checkbox reconciliation (fresh instance does this)
- Explanations of why decisions were made (plan already has context)
- Summaries of what the plan says (fresh instance will read it)

**Exception:** If leaving files intentionally uncommitted (WIP, needs review before commit), note in Resume Point:
> "Note: `foo.yaml` left uncommitted pending validation"
