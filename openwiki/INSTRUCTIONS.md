A code and operations wiki for this local Omni-Scale infrastructure repository. Prioritize a concise quickstart, architecture overview, practical source map, deployment and recovery workflows, domain concepts, operational troubleshooting, validation guidance, and integration boundaries.

Explain how the Omni Hub (`omni/`), Proxmox provider (`proxmox-provider/`), machine classes (`machine-classes/`), cluster templates and patches (`clusters/`), and operational scripts (`scripts/`) fit together. Make the network, DNS, authentication, persistent-state, and bootstrap dependencies explicit.

Respect the repository boundary: this repo owns the Omni-managed Talos substrate and the handoff into GitOps. Post-bootstrap platform applications belong to [basher83/mothership-gitops](https://github.com/basher83/mothership-gitops); document their substrate requirements and handoff points without treating their implementation as owned here. Reference that repository using its GitHub URL, not a local filesystem location.

Ground pages in current configuration, scripts, validation tooling, and existing deployment, operations, and troubleshooting documentation. Distinguish implemented behavior from plans, audit findings, and historical workarounds. Inspect recent git history when available to explain evolution and explicitly recorded rationale; do not invent motivations when evidence is unavailable.

Separate safe local checks from infrastructure-changing and destructive commands. Document prerequisites, execution context, expected outcomes, verification steps, and recovery limitations for important workflows.

Prefer practical navigation for engineers over generic summaries. Link to authoritative repository files instead of duplicating long runbooks, and exclude caches, virtual environments, and agent conversation history from primary documentation sources.
