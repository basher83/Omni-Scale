# Operational Troubleshooting

This document covers operational issues with the Omni + Proxmox provider. For deployment issues (container won't start, networking), see `docker/TROUBLESHOOTING.md`.

## Provider Registration Issues

### Provider Not Appearing in Omni

**Symptoms:** Provider doesn't show in Omni UI under Infrastructure Providers.

**Checks:**

```bash
# Verify provider is running
docker compose -f docker/compose.yaml ps proxmox-provider

# Check provider logs for registration attempts
docker compose -f docker/compose.yaml logs proxmox-provider | grep -i register
```

**Common causes:**

1. **Invalid provider key:** Regenerate key in Omni UI and update `.env`
2. **Network issue:** Provider can't reach Omni API (check MagicDNS resolution)
3. **Wrong Omni URL:** Verify `--omni-api-endpoint` matches your Omni domain

### Provider Shows "Unhealthy"

**Checks:**

```bash
# Check provider logs for errors
docker compose -f docker/compose.yaml logs --tail=50 proxmox-provider
```

**Common causes:**

1. **Proxmox API unreachable:** Test connectivity from host
2. **Invalid credentials:** Verify config.yaml settings
3. **SSL certificate issues:** Check `insecureSkipVerify` setting

## Storage Selector Issues

### CEL Selector Returns Empty

**Symptoms:** Machine provisioning fails with storage-related error.

**Checks:**

```bash
# On Proxmox node, list storage pools
pvesh get /storage

# Check storage types
pvesh get /storage --output-format json | jq '.[] | {storage, type, enabled, active}'
```

**Common causes:**

1. **Wrong storage type:** `lvmthin` vs `lvm` vs `zfspool`
2. **Storage not enabled/active:** Check Proxmox storage configuration
3. **Typo in storage name:** CEL expressions are case-sensitive

**Fix:** Update MachineClass storageSelector to match actual storage configuration.

### Wrong Storage Selected

**Cause:** Multiple storage pools match the filter.

**Fix:** Add more specific conditions:

```yaml
# Instead of
storageSelector: 'storage.filter(s, s.type == "rbd")[0].storage'

# Use
storageSelector: 'storage.filter(s, s.type == "rbd" && s.storage == "vm_ssd")[0].storage'
```

## Machine Provisioning Issues

### VMs Not Creating

**Symptoms:** MachineClass applied, but no VMs appear in Proxmox.

**Checks:**

```bash
# Check provider logs
docker compose -f docker/compose.yaml logs proxmox-provider | grep -i error

# Verify MachineClass is recognized
omnictl get machineclasses
```

**Common causes:**

1. **Insufficient Proxmox resources:** Check node capacity
2. **Invalid MachineClass config:** Missing required fields
3. **Proxmox permissions:** User lacks VM.Allocate permission

### VMs Created But Not Registering

**Symptoms:** VMs exist in Proxmox but don't appear in Omni.

**Checks:**

1. VM is booting and running
2. VM has network connectivity
3. Talos is installed correctly

**Common causes:**

1. **Network isolation:** Talos VMs can't reach Omni
2. **Wrong Talos ISO:** Provider using incompatible Talos version
3. **Firewall blocking:** Ports 50000-50001 (Siderolink)

### VMs Stuck in "Provisioning"

**Symptoms:** Machines show "Provisioning" indefinitely.

**Checks:**

```bash
# Check machine status
omnictl get machines

# Check specific machine
omnictl get machine <machine-id> -o yaml
```

**Common causes:**

1. **Talos bootstrap failed:** Check VM console in Proxmox
2. **Network issues:** VM can't reach Omni
3. **Resource constraints:** VM stuck waiting for resources

## Cluster Issues

### Cluster Creation Fails

**Symptoms:** Cluster template sync fails or cluster stays unhealthy.

**Checks:**

```bash
# Check cluster status
omnictl get cluster <cluster-name> -o yaml

# Check cluster events
omnictl get events --cluster <cluster-name>
```

**Common causes:**

1. **Invalid MachineClass reference:** MachineClass doesn't exist
2. **Insufficient machines:** Not enough healthy machines
3. **etcd issues:** Control plane quorum problems

### Cluster Scaling Problems

**Symptoms:** Adding workers fails or times out.

**Checks:**

```bash
# Check machine allocations
omnictl get machines --cluster <cluster-name>

# Verify MachineClass capacity
omnictl get machineclass <class-name> -o yaml
```

**Common causes:**

1. **MachineClass exhausted:** No available resources
2. **Provider at capacity:** Proxmox cluster full
3. **Rate limiting:** Too many simultaneous provisions

## omnictl Issues

### "Unauthorized" Errors

**Symptoms:** omnictl commands fail with authentication errors.

**Fixes:**

1. Re-authenticate: `omnictl login`
2. Check service account key validity
3. Verify key has required permissions

### "Connection Refused"

**Symptoms:** Can't connect to Omni.

**Fixes:**

1. Check Omni is running
2. Verify Tailscale connectivity
3. Test URL directly: `curl https://omni.your-tailnet.ts.net/healthz`

## Log Locations

| Component | Command |
|-----------|---------|
| Omni | `docker compose logs omni` |
| Provider | `docker compose logs proxmox-provider` |
| Tailscale sidecar | `docker compose logs omni-tailscale` |
| Machine logs | Omni UI → Machines → [machine] → Logs |

## Health Checks

Quick health verification:

```bash
# All services running
docker compose -f docker/compose.yaml ps

# Provider registered
omnictl get infraproviders

# Machines available
omnictl get machines

# Clusters healthy
omnictl get clusters
```
