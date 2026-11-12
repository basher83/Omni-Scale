# Files

- [Machine classes, templates and safe cluster changes](cluster-changes.md) - How Omni cluster templates reference Proxmox machine classes, and how to validate, preview, scale and roll out substrate changes safely. Covers production placement, Talos node contracts and live Hub compatibility gates.
- [Deploy the Hub and Proxmox provider](deploy-substrate.md) - Ordered first-deployment gates for Omni Hub identity, split-horizon networking, provider credentials, and live provisioning readiness. Use this workflow before applying machine classes or creating a cluster.
- [Destructive cluster rebuild and recovery limits](disaster-recovery.md) - Destructive Talos cluster rebuild through Omni, with exact readiness gates, diagnostic exits, manual secret handling, and the missing fresh-cluster Cilium step. Explains prerequisites, broad VM cleanup checks, and the boundary between infrastructure recreation and data restoration.
