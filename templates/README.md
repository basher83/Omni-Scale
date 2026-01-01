# Templates

Structural templates for consistent output formats.

## Available Templates

| Template | Approach | Use Case |
|----------|----------|----------|
| `plan-template.md` | Rigid schema | Full structure, automation-friendly, consistent |
| `plan-template-hybrid.md` | Soft + anchors | Flexible body, required Next Action + Critical Files |

## Choosing an Approach

| If... | Use |
|-------|-----|
| Plans feed into automation | Rigid (`plan-template.md`) |
| Human reads and executes | Hybrid (`plan-template-hybrid.md`) |
| Need consistent status tracking | Rigid |
| Content varies significantly per spec | Hybrid |
| Want parseable phase tables | Rigid |
| Want model to adapt structure to content | Hybrid |

## Usage Pattern

Reference in slash commands via `@templates/template-name.md`:

```markdown
## Plan Template

Use the structure defined in:
@templates/plan-template-hybrid.md
```

## Template Design Principles

**Rigid schema:**
- Section headers define required structure
- Tables define field schemas
- Placeholders show expected content
- Consistent across all outputs

**Hybrid (soft + anchors):**
- Soft guidelines for body ("cover these aspects")
- ONE anchoring requirement (Next Action section)
- Model freestyles structure within constraints
- Adapts to content complexity

## Creating New Templates

For rigid:
```markdown
# [Title]

## Required Section 1
[Description]

| Field | Value |
|-------|-------|

## Required Section 2
...
```

For hybrid:
```markdown
# [Title]

Write [output type] that is:
- [Quality 1]
- [Quality 2]

Cover these aspects:
- [Aspect 1]
- [Aspect 2]

---

## [Anchoring Section - REQUIRED]
[Specific format that MUST appear]
```
