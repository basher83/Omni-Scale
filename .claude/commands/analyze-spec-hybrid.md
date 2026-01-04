---
description: Analyze a spec file and generate a deployment plan (flexible structure)
allowed-tools: Bash(git:*), Bash(eza:*), Bash(test:*), Read, Write, AskUserQuestion
---

# Analyze Spec (Hybrid)

Generate a deployment plan using soft guidelines with anchored outputs.

## Variables

PLAN_TEMPLATE: `.claude/templates/plan-template`
PLAN_OUTPUT_DIRECTORY: `docs/plans/`

## Context

Spec contents:
@specs/gitops-bootstrap.yaml

## Instructions

- Create a implementation plan that is:
  - Concise enough to scan quickly
  - Detailed enough to execute effectively
  - Structured however best fits the content
- Cover: problem, solution, constraints, phases, blockers, risks
- **Required sections must appear exactly as specified:**

```markdown
## Next Action

**Phase:** [N]
**Task:** [Specific, concrete step]
**Command:** [Actual command or file to create]

## Critical Files

| File | Why Critical |
|------|--------------|
| [path] | [reason] |
```

- Save the complete implementation plan to `PLAN_OUTPUT_DIRECTORY/<descriptive-name>-hybrid.md`

## Workflow

1. **Understand**: Focus on the requirements provided and apply your assigned perspective throughout the design process

2. **Explore Throughly**:
   - Read any files provided to you in the initial prompt
   - Find existing patterns and conventions using GLOB, GREP, and READ tools
   - Understand the current architecture

3. **Design**:
   - Create implementation approach based on your perspective
   - Determine phases, dependencies, execution order
   - Consider trade-offs and architectural decisions

4. **Detail the Plan**:
   - Provide step-by-step implementation strategy
   - Identify dependencies and sequencing
   - Anticipate potential challenges
   - Let structure adapt to content—don't force sections that don't fit

## Report

After creating and saving the implementation plan, provide a concise report with the following format:

```text
✅ Implementation Plan Created

File: PLAN_OUTPUT_DIRECTORY/<descriptive-name>-hybrid.md
Topic: <brief description of what the plan covers>
Key Components:
- <main component 1>
- <main component 2>
- <main component 3>
```
