# omni-scale

Claude Code plugin for managing Sidero Omni + Proxmox infrastructure provider deployments.

## Commands

| Command | Description |
|---------|-------------|
| `/provider-setup` | Configure the Proxmox infrastructure provider for Omni |
| `/provider-status` | Check Proxmox provider status and verify connectivity |
| `/machineclass-create [name]` | Create and apply a MachineClass for Proxmox VM provisioning |
| `/cluster-status [cluster-name]` | Check status of Omni-managed Kubernetes clusters |

## Skills

### omni-proxmox

Core knowledge for Omni + Proxmox infrastructure integration. Automatically activates when working with:

- MachineClass creation and configuration
- CEL storage selectors
- Provider troubleshooting
- Cluster provisioning

Includes reference files for CEL syntax, Proxmox permissions, omnictl authentication, and troubleshooting.

## Structure

```text
plugin/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── provider-setup.md
│   ├── provider-status.md
│   ├── machineclass-create.md
│   └── cluster-status.md
└── skills/
    └── omni-proxmox/
        ├── SKILL.md
        ├── references/
        │   ├── cel-storage-selectors.md
        │   ├── proxmox-permissions.md
        │   ├── omnictl-auth.md
        │   └── troubleshooting.md
        └── examples/
            ├── machineclass-ceph.yaml
            ├── machineclass-local.yaml
            └── cluster-template.yaml
```

## Version

0.1.0

## License

MIT
