# Production Cluster Deployment Plan

**Generated:** 2026-01-03
**Spec:** specs/omni.yaml
**Status:** Phase 3b Ready to Execute

---

## Problem

Infrastructure is operational but no production workloads are running. The test cluster validated the
pipeline (SideroLink, VM provisioning, DNS). Now we need the actual production cluster: 3 control
plane nodes + 2 workers on Matrix's CEPH storage, with Cilium CNI for networking.

## Current State

| Component | Status |
|-----------|--------|
| Omni Hub | Running on Holly (192.168.10.20) |
| Proxmox Provider | Running on Foxtrot LXC (192.168.3.10) |
| Auth0 OIDC | Configured and working |
| Split-Horizon DNS | Configured (the four-day lesson) |
| Test cluster | Validated and destroyed |
| Machine classes | Created (matrix-control-plane, matrix-worker) |
| Cluster template | Created (clusters/talos-prod-01.yaml) |

## Constraints (Non-Negotiable)

These are battle-tested. Don't deviate.

| Constraint | Why |
|------------|-----|
| Proxmox hosts use Unifi Gateway DNS | VMs inherit DNS; must resolve omni.spaceships.work to LAN IP |
| CNI disabled in cluster template | Cilium requires kube-proxy disabled at bootstrap time |
| Provider on Matrix LXC | L2 adjacency required for SideroLink registration |
| storage_selector uses name only | CEL `type` keyword is reserved; can't filter by storage type |

---

## Phase 3b: Production Cluster Deployment

### Step 1: Apply Machine Classes

The classes exist but may not be applied to Omni yet.

```bash
omnictl apply -f machine-classes/matrix-control-plane.yaml
omnictl apply -f machine-classes/matrix-worker.yaml
omnictl get machineclasses
```

**Validation:** Both `matrix-control-plane` and `matrix-worker` appear in output.

### Step 2: Deploy Cluster

```bash
omnictl cluster template sync -f clusters/talos-prod-01.yaml
```

**What happens:**

1. Omni creates cluster object
2. Provider receives machine requests
3. Provider creates 5 VMs on Matrix (3 CP, 2 worker)
4. VMs PXE boot with Talos
5. Talos reaches omni.spaceships.work:8090 via LAN (Split-Horizon DNS)
6. SideroLink establishes WireGuard tunnel
7. Nodes appear in Omni UI

**Validation:** Watch Omni UI. All 5 nodes show green SideroLink checkmark within 10 minutes.

### Step 3: Monitor Provisioning

```bash
# Watch machine status
omnictl get machines -w

# Check cluster status
omnictl get clusters

# Provider logs (on Foxtrot LXC)
docker logs -f omni-provider-proxmox-provider-1
```

**Red flags to watch for:**

- SideroLink stuck at "Registering" → DNS issue, check Proxmox host DNS settings
- VMs created but immediately deleted → storage_selector mismatch
- Provider disconnected → service account key expired

### Step 4: Get Kubeconfig

Once control plane is Ready:

```bash
omnictl kubeconfig -c talos-prod-01 > ~/.kube/talos-prod-01.yaml
export KUBECONFIG=~/.kube/talos-prod-01.yaml

kubectl get nodes
# Expected: 3 control-plane (NotReady - no CNI), 2 workers (NotReady)
```

**Validation:** All 5 nodes exist, NotReady is expected (no CNI yet).

### Step 5: Install Cilium

Cluster has no CNI — nodes won't be Ready until Cilium is installed.

```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Install Cilium with Talos-specific settings
cilium install \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set gatewayAPI.enabled=true \
    --set gatewayAPI.enableAlpn=true \
    --set gatewayAPI.enableAppProtocol=true
```

**Validation:**

```bash
cilium status --wait
kubectl get nodes
# All 5 nodes should now show Ready
```

### Step 6: Verify Cluster Health

```bash
# Cilium connectivity test
cilium connectivity test

# Check core components
kubectl get pods -n kube-system

# Verify cluster info
kubectl cluster-info
```

**Validation:** All tests pass, no pods in CrashLoopBackOff.

---

## Phase 4: Tailscale Integration (Backlog)

After cluster is stable, deploy Tailscale Kubernetes Operator for workload access.
Not blocking for production cluster completion.

---

## Risks

| Risk | Mitigation |
|------|------------|
| CEPH storage unavailable | Check `pvesh get /storage` on Proxmox before deploy |
| VM creation exhausts resources | Matrix has 192GB RAM total; 5 VMs need ~72GB |
| Cilium install fails | Verify kube-proxy disabled in template, use exact Talos settings |

---

## Definition of Done

- [ ] 3 control plane nodes running and Ready
- [ ] 2 worker nodes running and Ready
- [ ] Cilium installed and healthy (`cilium status` shows OK)
- [ ] `kubectl get nodes` shows all 5 nodes Ready
- [ ] Cluster survives single node failure (test by stopping one VM)

---

## Next Action

**Phase:** 3b
**Task:** Apply machine classes and deploy production cluster
**Command:**

```bash
omnictl apply -f machine-classes/matrix-control-plane.yaml && \
omnictl apply -f machine-classes/matrix-worker.yaml && \
omnictl cluster template sync -f clusters/talos-prod-01.yaml
```

---

## Critical Files

| File | Why Critical |
|------|--------------|
| clusters/talos-prod-01.yaml | Cluster definition with CNI disabled for Cilium |
| machine-classes/matrix-control-plane.yaml | CP VM sizing (4 cores, 8GB, 40GB disk) |
| machine-classes/matrix-worker.yaml | Worker VM sizing (8 cores, 16GB, 100GB disk) |
| docs/guides/CILIUM.md | Talos-specific Cilium install commands |
| omni/compose.yml | Omni Hub config (for troubleshooting) |
