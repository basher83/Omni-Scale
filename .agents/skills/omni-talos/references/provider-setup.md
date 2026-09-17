# Provider Setup

The Proxmox provider runs as Docker containers inside the `omni-provider` LXC (CT 200) on Foxtrot.

## File Locations

| File | Purpose |
|------|---------|
| `proxmox-provider/compose.yml` | Docker Compose for provider + Tailscale sidecar |
| `proxmox-provider/config.yaml` | Proxmox API credentials (gitignored) |
| `proxmox-provider/.env` | Environment variables (gitignored) |

## Initial Setup

```bash
# Copy example files
cp proxmox-provider/config.yaml.example proxmox-provider/config.yaml
cp proxmox-provider/.env.example proxmox-provider/.env

# Edit with actual credentials
vim proxmox-provider/config.yaml  # Proxmox API token
vim proxmox-provider/.env         # Tailscale key, Omni service account

# Deploy
cd proxmox-provider
docker compose up -d
```

## Provider Config (config.yaml)

```yaml
proxmox:
  url: "https://192.168.3.5:8006/api2/json"
  tokenID: "terraform@pam!automation"
  tokenSecret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  insecureSkipVerify: true  # Self-signed Proxmox certs
```

For Proxmox API token setup, see `proxmox-permissions.md`.

## Environment Variables (.env)

```bash
TS_AUTHKEY=tskey-auth-xxx          # Tailscale auth key (reusable, ephemeral)
OMNI_SERVICE_ACCOUNT_KEY=xxx       # Omni service account key
```

## Provider Image

The `:local-fix` hostname workaround is historical, not a standing requirement.
Upstream [commit 559954c](https://github.com/siderolabs/omni-infra-provider-proxmox/commit/559954c759bd5b2cf319bcc0ac8c974bdb6621bb)
removed `configureHostname` and moved hostname delivery to NoCloud metadata.
Before selecting an image, establish the running digest and compare its build
revision with that change and the [current upstream releases](https://github.com/siderolabs/omni-infra-provider-proxmox/releases).
Neither `latest` nor `local-fix` proves image contents, freshness, or compatibility.

Read-only inspection inside the provider LXC (resolve the current container by
Compose service label, rather than assuming its generated name):

```bash
provider_container=$(docker ps -q --filter label=com.docker.compose.service=proxmox-provider)
# Expect exactly one result before continuing.
docker inspect --format '{{.Config.Image}} {{.Image}} {{.Created}}' "$provider_container"
provider_image=$(docker inspect --format '{{.Image}}' "$provider_container")
docker image inspect --format '{{json .RepoDigests}} {{json .Config.Labels}}' "$provider_image"
# From a workstation with buildx: query registry metadata without pulling/deploying.
docker buildx imagetools inspect ghcr.io/siderolabs/omni-infra-provider-proxmox:latest
```

Use registry platform manifests and upstream build logs to map the deployed
digest to source. If revision labels/build metadata are missing, compare the
running executable with the registry artifact before making a provenance claim.
Record dated digests and evidence in the incident/change record, not as a
permanent inventory here. The checked-in Compose `local-fix` reference is a
remaining desired-state reconciliation item; do not blindly deploy it over the
running stack. Review provider/Omni API compatibility before any image change.

## Verification

After deployment:

```bash
# Check live provider health; registration alone is insufficient.
omnictl get infraprovidercombinedstatus matrix-cluster
omnictl get infraproviderhealthstatus matrix-cluster

# Check provider status
scripts/provider-ctl.py --status

# Or inspect Omni's provider status objects directly
omnictl get infraproviderstatuses

# View provider logs
scripts/provider-ctl.py --logs 50
```
