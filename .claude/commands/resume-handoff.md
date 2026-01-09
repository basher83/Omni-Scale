---
description: Resume from a handoff brief to continue work
---

# Resume from Handoff

A previous session exhausted context mid-work. You are resuming that work.

**Principle:** Verify state, reconcile plan, then resume. Trust observations in handoff but verify external state independently.

---

## Startup Sequence

Execute in order:

### 0. Load Handoff

@.claude/handoff.local.md

If file doesn't exist stop, inform user and ask for context.

### 1. Establish Connection

Execute the connection command from handoff (first row of External State Mutations).

Verify you can reach the cluster:

```bash
kubectl get nodes
```

If connection fails, stop and troubleshoot before proceeding.

### 2. Check Repo State

```bash
# Working directory
git status -sb                      # Short status + branch tracking
git log --oneline -5                # Recent commits for context
git diff --stat                     # Changed files summary (staged + unstaged)

# Sibling repos (if referenced in handoff)
git -C ../mothership-gitops status -sb
git -C ../mothership-gitops log --oneline -5
```

Note:

- Uncommitted changes are WIP from previous session
- Check if changes are staged vs unstaged
- If clean, previous session committed everything

### 3. Load Context

Read in order:

1. **Handoff file**: `.claude/handoff.local.md` — what happened last session
2. **Plan file**: Path referenced in handoff Loop Position
3. **Spec file**: If referenced in handoff

### 4. Verify External State

For each row in "External State Mutations" table, run the verification command.

**Expected patterns:**

| Verification | Success Looks Like |
|--------------|-------------------|
| `kubectl get pods -n X` | Pods Running/Ready |
| `kubectl get clustersecretstores` | STATUS: Valid, READY: True |
| `kubectl get sc` | StorageClass exists, maybe (default) |
| `kubectl get applications -n argocd` | SYNC STATUS: Synced, HEALTH: Healthy |
| `(external service)` | Note in handoff, skip CLI verification |

**If verification fails:**

- Check if it's a known blocker (see Blockers Hit section)
- If blocker has workaround, apply it
- If new failure, this becomes a Fix cycle before resuming Build

Report verification results before proceeding.

### 5. Check Sibling Resources

If handoff references resources outside working directory (e.g., `../mothership-gitops`):

```bash
ls -la ../  # Check sibling exists
```

If missing, clone from remote URL in handoff. Don't re-create if it exists.

### 6. Reconcile Plan

Compare repo state + verified external state against plan tasks:

- Check off completed tasks
- Note partially complete tasks
- Update `updated_at` timestamp if plan has one

Commit plan updates if any:

```bash
git add docs/plans/*.md
git commit -m "chore: reconcile plan after session handoff"
```

### 7. Review Blockers

If handoff lists blockers:

- Assess if each blocker is resolved or still active
- If unresolved, determine if it blocks the resume point
- Note any that might recur (e.g., "Longhorn disk patch needed after cluster recreate")

### 8. Resume

Execute steps from "Resume Point" in handoff.

Start with Step 0 (connection) even if you already connected—handoff may specify a different context.

### 9. Cleanup

After successfully resuming (first task verification complete):

```bash
rm .claude/handoff.local.md
```

Handoff is consumed. Don't preserve it.

---

## Decision Points

### If external state verification fails

```text
→ Check Blockers Hit for known workaround
→ If known: Apply workaround, re-verify
→ If new: Enter Fix cycle, diagnose, resolve
→ Return to Resume Point when stable
```

### If plan and repo state conflict

```text
→ Trust repo state (it's what actually exists)
→ Trust verified external state over handoff claims
→ Update plan to match reality
→ Flag if conflict suggests wasted work or rollback
```

### If resume point is unclear or outdated

```text
→ Use Loop Position + verified state to determine actual next step
→ Don't blindly follow resume point if evidence contradicts it
→ When in doubt, ask user for clarification
```

### If sibling resource exists but differs from handoff

```text
→ Check git log in sibling repo for recent commits
→ Trust local state if it's ahead of what handoff describes
→ If behind or diverged, ask user which to use
```

---

## What NOT to Do

- Don't start work before verifying external state
- Don't trust handoff as authoritative—verify independently
- Don't clone repos that already exist locally
- Don't preserve handoff after consumption
- Don't re-read full conversation history (you don't have it—that's the point)
- Don't ask user for information that's in the handoff or plan

---

## Completion Report

After resuming successfully, briefly report:

```text
Resumed from handoff.

Verified:
- [x] Cluster connection (5 nodes)
- [x] ArgoCD (healthy)
- [x] Longhorn (default SC)
- [ ] Issue: X needed workaround Y

Reconciled plan: 3 tasks marked complete

Now executing: [Resume Point Step N]
```

Then continue with the work.
