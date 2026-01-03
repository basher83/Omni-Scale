---
description: Analyze a spec file and generate a deployment plan with current status
allowed-tools: Bash(git:*), Bash(eza:*), Bash(test:*), Read, Write, AskUserQuestion
---

# Analyze Spec

Generate a deployment plan by analyzing a spec file against current repo state.

## Variables

PLAN_TEMPLATE: `templates/plan-template.md`
PLAN_OUTPUT_DIRECTORY: `docs/plans/`

## Context

Spec contents:
@specs/omni.yaml

## Instructions

- Create a implementation plan using the PLAN_TEMPLATE that includes:
  - **The Problem** — Core challenge the spec addresses
  - **The Solution** — High-level approach
  - **Locked Decisions** — Constraints from spec
  - **Phases** — Ordered work breakdown with dependencies
  - **Phase Details** — Tasks, validation criteria, outputs per phase
  - **Next Action** — Single concrete step
  - **Risk Register** — What could go wrong
- Save the complete implementation plan to `PLAN_OUTPUT_DIRECTORY/<descriptive-name>.md`

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

## Report

After creating and saving the implementation plan, provide a concise report with the following format:

```text
✅ Implementation Plan Created

File: PLAN_OUTPUT_DIRECTORY/<descriptive-name>.md
Topic: <brief description of what the plan covers>
Key Components:
- <main component 1>
- <main component 2>
- <main component 3>
```
