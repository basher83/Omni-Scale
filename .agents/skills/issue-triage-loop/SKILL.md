---
name: issue-triage-loop
description: >
  Enumerate documented and latent open work scattered across a repo (audit
  reports, roadmaps, plan docs, TODO markers, local scratch files), deconflict
  it against git history and reality, and triage it into GitHub tracking.
when_to_use: >
  Use when a repo has accumulated audit reports, roadmap/plan docs, or inline
  markers that were never reconciled into a tracker, when the user asks "what
  needs tracking vs what's just docs", or before adopting GitHub issues as the
  single source of truth for open work.
---

<!-- MIGRATE: this skill is repo-agnostic and parked here temporarily.
     Operator reminder (2026-07-20): migrate ASAP to the global skills repo
     (lunar-claude) and consume via skills-lock. Tracked in issue #20. -->

# Issue Triage Loop

Enumeration → compile → assess → triage. Turn scattered documented findings
into a single tracker without creating garbage issues. The human approves the
triage plan; the agent executes everything else.

## Guardrails

- **Never create issues from raw enumeration.** Most findings are already
  fixed, permanent constraints, or false positives. Every finding needs an
  evidence-backed status before it can become an issue.
- **Present the triage proposal and get approval before creating anything.**
  Issue creation is outward-facing; the human decides the split.
- **One tracker.** The loop's end state includes demoting the source
  artifacts (roadmap backlogs, audit reports) to pointers — otherwise you've
  added a tracker, not consolidated one.

## Phase 1 — Enumerate (parallel subagents, disjoint beats)

Fan out read-only agents, one per source class, with explicit exclusions so
beats don't overlap. Typical split:

1. **Formal audit artifacts** — audit reports, `*.local.md` scratch audits,
   plan docs. Also determine each file's provenance: date, git-tracked vs
   local-only, and whether artifacts are independent or derived from each
   other.
2. **Docs corpus** — roadmaps, runbooks, troubleshooting guides, plans.
3. **Inline markers** — TODO/FIXME/HACK, commented-out config with rationale
   comments, "local-fix"/workaround pins, stubbed script paths.

Every agent prompt must include:

- **Per-item output contract**: source `file:line`, one-sentence claim,
  apparent status (`open | likely-resolved | unclear`) **with git evidence**
  (cite the commit if likely-resolved — make agents run `git log` against
  the files a finding touches), and cross-references for overlaps.
- **A freshness baseline**: current versions, dates, and recently-completed
  work the agent can't know — stale findings are the norm, not the exception.
- **The taxonomy, stated explicitly**: (a) trackable open work, (b) permanent
  documented constraint ("never do X" is docs, not an issue), (c) dead weight
  to delete. Agents must bucket, not dump — raw pattern hits are mostly
  false positives (template field names, changelog regexes, example
  placeholders).
- "No file dumps. Your final message is the deliverable."

## Phase 2 — Compile

Merge the agent reports in the main context, which holds what the agents
don't: live infrastructure state, work completed this session, repo-boundary
knowledge. Deduplicate findings that multiple agents saw from different
angles (the same debt often appears as a code comment, a troubleshooting
entry, and a roadmap item — that's one issue, not three).

## Phase 3 — Assess

- Spot-check `likely-resolved` claims against the current tree before
  accepting them.
- Route ownership: if the repo has a documented boundary ("post-bootstrap
  work belongs in repo X"), findings crossing it get filed with an explicit
  ownership note — or in the other repo, per the human's call.
- Separate **decision items** (open questions only the human can answer)
  from **work items**. Decisions become `question`-labeled issues stating
  "no work until decided".

## Phase 4 — Triage (approval-gated)

Present the proposal: what becomes an issue, what stays docs, what gets
deleted, and the consolidation. Rules that keep the issue count honest:

- **Consolidate small fixes** into one checklist issue burnable in a single
  session. Twenty one-line doc fixes are one issue, not twenty.
- **Defer upstream feature-asks with no active pain** — they go stale.
- Big items get one issue each, milestone-worthy items flagged.

After approval, create issues with cold-start bodies: enough context to be
picked up by a future session with zero conversation history — source
`file:line` references, why it's trackable, acceptance criteria, ownership
notes, and any operator-approval gates (e.g. "human reviews the upstream
posting before submission").

## Close the loop

The last checklist items of any triage are self-referential and go into the
consolidated issue:

- Append resolution status to the audit artifacts so the next audit doesn't
  re-litigate fixed findings.
- Migrate surviving roadmap/backlog entries into issues and demote the
  roadmap to a pointer.
- Fix any dangling "tracked in X" pointers to reference the real issue.

## Failure handling

- An agent returns file dumps or unbucketed grep hits: re-dispatch with the
  output contract restated; do not compile garbage.
- Two source artifacts disagree about the same file: report both readings to
  the human — do not average them.
- Unclear whether something is resolved: mark it a verification checklist
  item in the consolidated issue rather than guessing either way.
