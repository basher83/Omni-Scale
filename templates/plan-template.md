# [Spec Name] Deployment Plan

**Generated:** [YYYY-MM-DD]
**Spec:** [path/to/spec.yaml]
**Status:** [Planning | In Progress | Blocked | Complete]

---

## The Problem

[1-2 paragraphs explaining the core challenge. What's broken, missing, or needed? What's the bootstrap problem or dependency constraint? Why can't we just do the obvious thing?]

## The Solution

[2-3 sentences on high-level approach. What's the key insight that unlocks the solution? What's the architectural decision that makes this work?]

---

## Locked Decisions

Constraints from spec that are non-negotiable:

| Decision | Value | Rationale |
|----------|-------|-----------|
| [decision-name] | [value] | [why this was locked] |
| [decision-name] | [value] | [why this was locked] |

---

## Phases

| Phase | Name | Status | Dependencies | Notes |
|-------|------|--------|--------------|-------|
| 1 | [Phase Name] | Not started | None | [Key deliverable or constraint] |
| 2 | [Phase Name] | Not started | Phase 1 | [Key deliverable or constraint] |
| 3 | [Phase Name] | Blocked by Phase N | Phase 1, 2 | [Key deliverable or constraint] |

### Status Values

| Status | Meaning |
|--------|---------|
| Not started | Work hasn't begun |
| In progress | Actively being worked |
| Blocked by X | Waiting on dependency |
| Complete | Done and verified |

---

## Phase Details

### Phase 1: [Name]

**Objective:** [What this phase accomplishes]

**Prerequisites:** [What must be true before starting]

**Tasks:**
- [ ] Task 1: [Concrete action]
- [ ] Task 2: [Concrete action]
- [ ] Task 3: [Concrete action]

**Validation:** [How we know this phase is complete]

**Outputs:** [Artifacts produced - files, configs, deployed resources]

---

### Phase 2: [Name]

**Objective:** [What this phase accomplishes]

**Prerequisites:** [What must be true before starting - reference Phase 1 outputs]

**Tasks:**
- [ ] Task 1: [Concrete action]
- [ ] Task 2: [Concrete action]

**Validation:** [How we know this phase is complete]

**Outputs:** [Artifacts produced]

---

## Next Action

**Phase:** [N]
**Task:** [Specific, concrete, actionable step]
**Command:** [If applicable - actual command to run or file to create]

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| [What could go wrong] | [High/Medium/Low] | [How to prevent or recover] |

---

## Change Log

| Date | Change | Phase Affected |
|------|--------|----------------|
| [YYYY-MM-DD] | Initial plan generated | All |
