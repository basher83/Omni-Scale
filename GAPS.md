# omni-scale Plugin Implementation Gaps

Analysis of PLAN.md against plugin-dev specifications. Gaps must be addressed before implementation.

## Critical Gaps

### GAP-01: Plugin Manifest Content

PLAN.md specifies `.claude-plugin/plugin.json` exists but doesn't define content.

**Required fields:**

- `name`: "omni-scale" (specified)
- `version`: Not specified
- `description`: Not specified
- `author`: Not specified

**Needs answer:** What metadata values?

**Answer:**

```json
{
  "name": "omni-scale",
  "version": "0.1.0",
  "description": "Omni + Proxmox infrastructure provider management for Talos clusters",
  "author": "basher83"
}
```

---

### GAP-02: Skill Description Format

**Current (PLAN.md):**
> "Core knowledge for Omni + Proxmox infrastructure provider. Use when deploying Talos clusters..."

**Required format (third-person with triggers):**
> "This skill should be used when the user asks to 'create a machine class', 'configure Proxmox provider', 'debug provider registration', 'set up CEL storage selectors', or needs guidance on Omni + Proxmox integration."

---

### GAP-03: Command Naming Convention

PLAN.md shows nested structure:

```text
commands/provider/setup.md
```

This creates namespaced command `/setup (plugin:omni-scale:provider)`.

**Options:**

1. Flat: `commands/provider-setup.md` → `/provider-setup`
2. Nested: `commands/provider/setup.md` → `/setup` (namespaced)

**Needs answer:** Which naming approach?

---

### GAP-04: Command Body Content

PLAN.md provides workflow descriptions but not actual command content.

**Example - what's specified:**

```text
/provider-setup workflow:
1. Check prerequisites
2. Create config.yaml
3. Prompt for key
...
```

**What's needed:**

```markdown
---
description: Configure Proxmox infrastructure provider
allowed-tools: Bash, Write, Read
---

Check prerequisites first:
1. Verify docker compose is available
2. Check if Omni is accessible at the configured endpoint
3. Test Proxmox API connectivity
...
```

---

### GAP-05: SKILL.md Body Content

Only outline provided. Need ~1,500-2,000 words of actual content covering:

- Architecture (Omni → Provider → Proxmox → Talos VMs)
- Provider configuration
- MachineClass structure
- Common operations
- Links to references

---

### GAP-06: State File Operations

Commands reference state operations without implementation details.

**Questions:**

- How to parse YAML frontmatter in commands?
- How to update individual fields?
- Should there be an init command to create state from example?

**Answer:**

No init command.

- Commands create state file on first meaningful operation (provider-setup writes initial state)
- Use yq for YAML parsing/updates in bash, or let Claude handle it directly since commands are prompts, not scripts
- State file is simple enough Claude can read/write it inline

---

### GAP-07: Docker Working Directory

Commands use `docker compose` but need to specify working directory.

**Options:**

1. Use `docker compose -f docker/compose.yaml`
2. Instruct Claude to `cd docker` first
3. Use absolute path with ${CLAUDE_PROJECT_DIR}

**Answer:**

**Explicit -f flag**

```bash
docker compose -f ${CLAUDE_PROJECT_DIR}/docker/compose.yaml ...
```

**Reasons:**

- Works regardless of current directory
- Explicit is better than implicit
- `${CLAUDE_PROJECT_DIR}` available in plugin context (see CLAUDE.md)

---

### GAP-08: omnictl Access Method

Commands assume `omnictl` is available but don't specify how.

**Options:**

1. Installed locally (user responsibility)
2. Run via docker exec into omni container
3. Download as part of setup

**Answer**

1. Option 3 (download on first use) with detection of existing installation.

- Considerations for this specific architecture:

Docker exec won't work cleanly—Omni runs on a remote VM (192.168.10.20), so you'd need SSH → docker exec, which is fragile.

**Implementation sketch:**

```bash
OMNICTL_DIR="${XDG_DATA_HOME:-$HOME/.local}/bin"
OMNICTL_PATH="$OMNICTL_DIR/omnictl"

## Check PATH first (respect existing installs)

if command -v omnictl &>/dev/null; then
  OMNICTL="omnictl"
elif [ -x "$OMNICTL_PATH" ]; then
  OMNICTL="$OMNICTL_PATH"
else

## Download for platform

  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  curl -fsSL "<https://github.com/siderolabs/omni/releases/latest/download/omnictl-${OS}-${ARCH}>" -o "$OMNICTL_PATH"
  chmod +x "$OMNICTL_PATH"
  OMNICTL="$OMNICTL_PATH"
fi
```

Auth consideration: omnictl needs --omni-url and auth. Options:

Service account key (already have OMNI_INFRA_PROVIDER_KEY)
Browser-based OIDC flow (interactive)

## For automation, service account with appropriate permissions is cleaner. Could reuse existing key or create a dedicated onenene

---

## Important Gaps

### GAP-09: No Hooks Defined

Hooks could enhance workflow:

- `SessionStart`: Remind about state file if missing
- `Stop`: Verify state updates after changes

**Decision needed:** Include in v1 or defer?

---

### GAP-10: No Agents Defined

Potential agents:

- `cluster-deployer`: Full deployment automation
- `troubleshooter`: Diagnosis workflow

**Decision needed:** Include in v1 or defer?

**Answer:**

Recommendation: Option 1 (Commands + Skills only)
Rationale:

| Feature | Value for v1 | Complexity |
|---------|--------------|------------|
| Commands | Core functionality | Medium |
| Skills | Reference material, examples | Low |
| SessionStart hook | Nice-to-have (state loading) | Low-medium |
| Agents | Multi-step workflows | High |

Why defer hooks/agents:

Commands can self-load state - A command like provider-status can read .claude/omni-scale.local.md when it runs. No hook needed.
Unclear agent boundaries - What workflow needs an agent? "Create cluster" is multi-step but could be a single command that prompts for inputs vs. an agent that takes over.
Ship and iterate - Get the commands working, use them in anger, then you'll know what hooks/agents would actually help.

v1 scope:

```text
omni-scale/
├── commands/
│ ├── provider-setup.md
│ ├── provider-status.md
│ ├── machineclass-create.md
│ └── cluster-status.md
├── skills/
│ └── omni-proxmox/
│ ├── SKILL.md
│ ├── references/
│ └── examples/
└── settings.md
```

v2 candidates (if needed):

SessionStart hook to surface provider health
Agent for guided cluster creation with validation gates

---

### GAP-11: Reference File Content

Listed files lack actual content:

- `cel-storage-selectors.md`
- `proxmox-permissions.md`
- `troubleshooting.md`

---

### GAP-12: machine-classes Directory

Commands save to `machine-classes/[name].yaml` but location not defined.

**Questions:**

- Project root or under `.claude/`?
- Gitignored or committed?

**Answer:**

Option 1 (machine-classes/ at root)
MachineClass YAMLs are infrastructure-as-code—same category as Terraform modules or Ansible roles. They define:

Resource specs (CPU, memory, disk)
Storage selectors (CEPH pools)
Node targeting
Network config

None of that is secret or user-specific. It's declarative infrastructure you want version controlled.
Structure:

```text
Omni-Scale/
├── machine-classes/
│ ├── matrix-worker.yaml # Production workers on Matrix cluster
│ ├── matrix-controlplane.yaml
│ └── dev-small.yaml # Smaller VMs for testing
├── docker/
│ └── ...
```

What stays gitignored (in .env or .claude/):

`OMNI_INFRA_PROVIDER_KEY`
Endpoint URLs if they vary per user
Local state (`.claude/omni-scale.local.md`)

Bonus: Committed machine classes become self-documenting. Future-you (or teammates) can see exactly what VM specs are available without digging through Omni UIUI.

---

### GAP-13: Tool Availability Checks

Commands assume docker, omnictl, curl exist.

**Need:** Error handling when tools missing.

---

### GAP-14: Provider Key Instructions

PLAN.md mentions prompting for key but not how to generate it.

**Need:** Instructions linking to Omni UI for key generation.

---

## Questions Summary

| Gap | Question |
|-----|----------|
| GAP-01 | What plugin version/description/author? |
| GAP-03 | Flat or namespaced commands? |
| GAP-06 | Init command for state file? |
| GAP-07 | Docker working directory approach? |
| GAP-08 | How is omnictl accessed? |
| GAP-09 | Include hooks in v1? |
| GAP-10 | Include agents in v1? |
| GAP-12 | machine-classes location? |
