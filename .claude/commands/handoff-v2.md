---
description: Produce a handoff brief for a fresh instance to continue work
---

# Session Handoff

Context is exhausted. Produce a handoff brief for a fresh Claude Code instance to continue this work.

**Principle:** Report observations, not synthesis. Capture state not recoverable from repo or plan. Every element must be independently verifiable or executable by a fresh instance with zero conversation context.

## Context

Conversation contents:

- `docs/gitops-boot-convo.txt`
- `docs/gitops-boot-convo-500-1000.txt`
- `docs/gitops-boot-convo-end.txt`

## Output Location

`.claude/handoff.local.md` (overwrite if exists)

---

## Required Sections

### 1. Loop Position

State explicitly:

- **Phase**: Plan | Build | Review | Fix
- **Status**: (active | ready to start | blocked)
- **Detail**: Task name/number from plan, or what's being reviewed/fixed
- **Reference**: Path to spec or plan file with section

Example:

```text
**Build — Phase 5: Validation & Documentation (ready to start)**

See `specs/gitops-bootstrap.yaml` phase_5 for tasks and exit criteria.
```

### 2. External State Mutations

Actions taken outside the repo that a fresh instance can't see via `git diff`.

**Table format with verification column:**

| What | Action Taken | Verified? |
|------|--------------|-----------|
| kubectl context | How to connect | `command to verify` |
| Resource name | What was done | `kubectl get ...` or "(external service)" |

**Requirements:**

- First row: kubectl context or connection method
- Each row must include verification command OR note "(external - cannot verify from CLI)"
- **Sibling directory rule:** Resources created outside working directory must include relative local path AND remote URL
  - ✅ `Created at ../mothership-gitops (github.com/user/repo)`
  - ❌ `Created repo at github.com/user/repo`
- Cluster resources: include namespace and kubectl command
- External services (Infisical, cloud consoles): note explicitly

**Include only mutations that occurred. Skip section if none.**

Categories to consider:

- Repos/directories created outside working directory
- Namespaces, secrets, configmaps created manually (not via manifest)
- Resources deployed via helm (not tracked in working repo)
- Configuration applied to remote systems (node patches, labels)
- External service changes (IAM, secrets managers, DNS)

### 3. Blockers Hit

Errors or unexpected behaviors encountered. Each blocker must be self-contained and actionable.

**Format:**

```text
[Short description]
- Symptom: What you observed
- Workaround: Full executable command(s)
- Root cause: Why it happened (if known)
```

**Requirements:**

- Commands must be copy-paste executable (no `<placeholders>` without showing actual values used)
- If command is long/complex, include the full JSON/YAML
- If workaround references conversation history, note: "See exported conversation for details"

**Skip section if no blockers.**

### 4. Resume Point

One imperative sentence, then numbered steps with executable commands.

**Requirements:**

- Step 0: Connection/context setup if needed
- Each step: Actual command, not description
- External resources: Full path or URL (relative paths OK if from working directory)
- Reference spec/plan sections rather than duplicating content: "See `specs/foo.yaml` section X"
- End state: What "done" looks like

Example:

```markdown
Run Phase 5 recovery test, then document in mothership-gitops README.

Steps:
0. Connect: omnictl kubeconfig
1. Destroy: omnictl cluster delete talos-prod-01
2. Recreate: omnictl cluster template sync -f clusters/talos-prod-01.yaml
3. Bootstrap (see specs/gitops-bootstrap.yaml bootstrap section):

kubectl create namespace external-secrets
kubectl create secret generic universal-auth-credentials \
    --from-literal=clientId=$INFISICAL_CLIENT_ID \
    --from-literal=clientSecret=$INFISICAL_CLIENT_SECRET \
    --from-literal=clientSecret=$INFISICAL_CLIENT_SECRET \
    -n external-secrets
kubectl apply -f ../mothership-gitops/bootstrap/bootstrap.yaml


4. Verify: `kubectl get applications -n argocd` (all Healthy)
5. Update README at `../mothership-gitops/README.md`
6. Mark complete in `kernel.md`
```

---

## What NOT to Include

- File changes (recoverable via `git diff`)
- Learnings or pattern extraction (defer to `/complete-plan`)
- Plan updates or checkbox reconciliation (fresh instance does this)
- Explanations of why decisions were made (plan already has context)
- Summaries of what the plan says (fresh instance will read it)
- Commands with unexpanded placeholders

**Exception:** If leaving files intentionally uncommitted (WIP, needs review before commit), note in Resume Point:
> "Note: `foo.yaml` left uncommitted pending validation"

---

## Self-Check Before Writing

Before writing the handoff file, verify:

- [ ] Can a fresh instance connect to the cluster? (Context documented)
- [ ] Can each external mutation be independently verified? (Commands included)
- [ ] Are sibling directories referenced by local path? (Not just remote URL)
- [ ] Are blocker workarounds copy-paste executable? (No placeholders)
- [ ] Can Resume Point steps be executed without clarifying questions?

If any check fails, fix before writing.
