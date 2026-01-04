# GitOps Bootstrap Deployment Plan

**Generated:** 2026-01-04
**Spec:** specs/gitops-bootstrap.yaml
**Target Cluster:** talos-prod-01 (3 CP + 2 workers, operational)

---

## Problem Statement

The production Talos cluster is operational but naked. No persistent storage, no secrets
management, no service exposure, no monitoring. Every workload deployment is manual.

Need a GitOps foundation where a single `kubectl apply` bootstraps the entire stack, and
ArgoCD manages everything from Git thereafter.

## Solution

App of Apps pattern with sync waves. Bootstrap ArgoCD first (no dependencies), then chain:
ESO, Tailscale Operator, Longhorn, Netdata, ArgoCD HA upgrade. One manual secret (Infisical
credentials) breaks the chicken-and-egg problem. Everything else flows from Git.

---

## Current State

| Component | Status |
|-----------|--------|
| talos-prod-01 cluster | Operational (5 nodes Ready, Cilium CNI) |
| mothership-gitops repo | Does not exist |
| ArgoCD | Not deployed |
| Longhorn | Not deployed (worker patches ready in cluster template) |
| External Secrets | Not deployed |
| Infisical project | Ready: `mothership-s0-ew` (secrets populated) |

The cluster template (`clusters/talos-prod-01.yaml`) already includes Longhorn mount patches
for workers.

---

## Locked Decisions

| Decision | Value | Rationale |
|----------|-------|-----------|
| Repository | `mothership-gitops` (separate repo) | Different change cadences |
| Bootstrap pattern | App of Apps + sync waves | Single entry point, ordered deployment |
| Secrets bootstrap | One manual secret for Infisical | Breaks ESO chicken-and-egg |
| Longhorn replicas | 2 (Golf + Hotel workers) | Control planes shouldn't run storage |
| ArgoCD HA | Bootstrap non-HA, self-upgrade | Non-HA needs no PVCs |
| ArgoCD TLS | --insecure | Tailscale terminates TLS |

---

## Sync Wave Order

```text
Wave 1: ArgoCD (non-HA)     <- Included directly in bootstrap.yaml
Wave 2: ESO + CRDs          <- First ArgoCD Application
Wave 3: ClusterSecretStore  <- Depends on ESO + manual secret
Wave 4: Tailscale Operator  <- Secrets from ESO
Wave 5: Longhorn            <- Provides PVCs
Wave 6: Netdata             <- Secrets from ESO
Wave 99: ArgoCD HA upgrade  <- Manual sync, needs Longhorn
```

---

## Phases

### Phase 1: Repository Setup

**Status:** Not started
**Depends on:** Nothing
**Exit criteria:** bootstrap.yaml applies to empty cluster without errors

Tasks:

1. Create `mothership-gitops` GitHub repository
2. Initialize directory structure:

   ```text
   bootstrap/
     bootstrap.yaml      # kubectl apply entry point
     namespace.yaml
   apps/
     root.yaml           # App of Apps
     argocd/             # ArgoCD manifests
     external-secrets/
     tailscale-operator/
     longhorn/
     netdata/
   ```

3. Create ArgoCD namespace + non-HA installation in bootstrap.yaml
4. Create root.yaml (App of Apps pointing to apps/)
5. Configure Renovate for Helm chart version tracking

**Validation:** `kubectl apply -f bootstrap/bootstrap.yaml` creates argocd namespace and pods

### Phase 2: Core Infrastructure Apps

**Status:** Not started
**Depends on:** Phase 1
**Exit criteria:** ClusterSecretStore shows `Ready`

Tasks:

1. Create ESO Application (Helm chart + values)
2. Create ClusterSecretStore manifest (references manual secret, points to `mothership-s0-ew`)
3. Document manual secret creation command

**Validation:**

```bash
kubectl get clustersecretstores infisical -o jsonpath='{.status.conditions[0].status}'
# Should return "True"
```

### Phase 3: Platform Services

**Status:** Not started
**Depends on:** Phase 2
**Exit criteria:** All platform pods running, Longhorn StorageClass default

Tasks:

1. Create Tailscale Operator Application with ExternalSecret for OAuth
2. Create Longhorn Application (2 replicas, default StorageClass)
3. Create Netdata Application with ExternalSecret for claiming

**Validation:**

```bash
kubectl get sc longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'
# Should return "true"

kubectl get pods -n tailscale-operator | grep Running
kubectl get pods -n longhorn-system | grep Running
kubectl get pods -n netdata | grep Running
```

### Phase 4: ArgoCD HA Upgrade

**Status:** Not started
**Depends on:** Phase 3 (specifically Longhorn healthy)
**Exit criteria:** Redis HA running, ArgoCD pods have 2 replicas

Tasks:

1. Create ArgoCD HA Application (sync-wave 99, manual sync)
2. Wait for Longhorn to provision PVCs
3. Trigger manual sync via ArgoCD UI or CLI

**Validation:**

```bash
kubectl get pods -n argocd | grep redis
# Should show redis-ha pods

kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server | wc -l
# Should return 2+
```

### Phase 5: Validation & Documentation

**Status:** Not started
**Depends on:** Phase 4
**Exit criteria:** Recovery procedure tested, documentation complete

Tasks:

1. Test recovery: delete cluster, run bootstrap, verify all services recover
2. Document bootstrap procedure in repo README
3. Update kernel.md with new initiative status
4. Cross-reference from Omni-Scale ROADMAP

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Infisical Universal Auth rate limits | Low | Medium | Use service account |
| Helm chart version incompatibilities | Medium | Low | Renovate + pinned versions |
| Longhorn storage exhaustion | Low | High | Monitor, set resource quotas |
| ESO startup race with ClusterSecretStore | Medium | Medium | Sync waves ensure ordering |

---

## Bootstrap Procedure (Final)

```bash
# Prerequisites
# - kubectl configured via Omni proxy
# - Infisical credentials ready

# Step 1: Create the one manual secret
kubectl create namespace external-secrets
kubectl create secret generic universal-auth-credentials \
  --from-literal=clientId=<INFISICAL_CLIENT_ID> \
  --from-literal=clientSecret=<INFISICAL_CLIENT_SECRET> \
  -n external-secrets

# Step 2: Bootstrap GitOps
kubectl apply -f https://raw.githubusercontent.com/<user>/mothership-gitops/main/bootstrap/bootstrap.yaml

# Step 3: Monitor
watch kubectl get applications -n argocd

# Step 4: After Longhorn healthy, trigger HA upgrade
argocd app sync argocd-ha
```

---

## Definition of Done

- [ ] Single bootstrap command deploys entire stack
- [ ] All components managed via ArgoCD Applications
- [ ] Secrets sourced from Infisical via ESO
- [ ] Services accessible via Tailscale (no public exposure)
- [ ] Persistent storage available via Longhorn
- [ ] Cluster monitoring operational via Netdata
- [ ] ArgoCD running in HA mode with persistent storage
- [ ] Recovery procedure documented and tested

---

## Next Action

**Phase:** 1
**Task:** Create mothership-gitops repository with directory structure
**Command:**

```bash
gh repo create mothership-gitops --private --clone
cd mothership-gitops
mkdir -p bootstrap apps/{argocd,external-secrets,tailscale-operator,longhorn,netdata}
```

---

## Critical Files

| File | Why Critical |
|------|--------------|
| `bootstrap/bootstrap.yaml` | Single entry point for entire stack |
| `apps/root.yaml` | App of Apps orchestrator |
| `apps/external-secrets/clustersecretstore.yaml` | Connects to Infisical |
| `apps/longhorn/values.yaml` | Storage config (replicas, default class) |
| `clusters/talos-prod-01.yaml` | Has Longhorn mount patches (existing) |
