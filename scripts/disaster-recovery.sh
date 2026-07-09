#!/usr/bin/env bash
set -euo pipefail

#
# Omni-Scale Disaster Recovery Script
#
# Destroys talos-prod-01 cluster and recreates from declarative specs.
# Expected runtime: 30-45 minutes
#
# Prerequisites:
#   - omnictl authenticated
#   - kubectl available
#   - Tailscale SSH access to Foxtrot, Golf, and Hotel
#   - Infisical credentials available for manual secret creation
#
# Usage:
#   ./scripts/disaster-recovery.sh
#

# Configuration. Defaults follow the checked-in repo layout; environment variables
# allow deployment-specific overrides without editing this script.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
LAB_ROOT=$(cd -- "$REPO_ROOT/.." && pwd)

CLUSTER_NAME="${CLUSTER_NAME:-talos-prod-01}"
CLUSTER_TEMPLATE="${CLUSTER_TEMPLATE:-$REPO_ROOT/clusters/talos-prod-01.yaml}"
GITOPS_BOOTSTRAP="${GITOPS_BOOTSTRAP:-$LAB_ROOT/mothership-gitops/bootstrap/bootstrap.yaml}"
EXPECTED_MACHINES="${EXPECTED_MACHINES:-6}"
PROXMOX_HOSTS=(foxtrot golf hotel)
PROVIDER_CTL="${PROVIDER_CTL:-$REPO_ROOT/.agents/skills/omni-talos/scripts/provider-ctl.py}"

# Timeouts (seconds)
TIMEOUT_VM_DESTROY=600
TIMEOUT_MACHINES_READY=1200
TIMEOUT_API_READY=600
TIMEOUT_NODES_READY=600
TIMEOUT_ARGOCD_READY=300
TIMEOUT_APPS_SYNCED=1200

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Timing
START_TIME=$(date +%s)
declare -A PHASE_TIMES

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; }

record_phase_time() {
  local phase="$1"
  PHASE_TIMES["$phase"]=$(($(date +%s) - START_TIME))
}

# Poll until condition is met or timeout
poll_until() {
  local description="$1"
  local check_cmd="$2"
  local timeout_seconds="$3"
  local failure_cmd="$4"

  local elapsed=0
  local interval=10

  log "Waiting: ${description} (timeout: ${timeout_seconds}s)"

  while ! eval "$check_cmd" 2>/dev/null; do
    sleep "$interval"
    elapsed=$((elapsed + interval))

    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      error "TIMEOUT: ${description} after ${timeout_seconds}s"
      echo "--- Failure diagnostics ---"
      eval "$failure_cmd" || true
      return 1
    fi

    printf "  ... %ds elapsed\r" "$elapsed"
  done

  echo ""
  log "Complete: ${description} (${elapsed}s)"
  return 0
}

# Check prerequisites
check_prerequisites() {
  log "Checking prerequisites..."

  if ! command -v omnictl &>/dev/null; then
    error "omnictl not found in PATH"
    exit 1
  fi

  if ! command -v kubectl &>/dev/null; then
    error "kubectl not found in PATH"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    error "jq not found in PATH"
    exit 1
  fi

  if [ ! -f "$CLUSTER_TEMPLATE" ]; then
    error "Cluster template not found: $CLUSTER_TEMPLATE"
    exit 1
  fi

  if [ ! -f "$GITOPS_BOOTSTRAP" ]; then
    error "GitOps bootstrap not found: $GITOPS_BOOTSTRAP"
    exit 1
  fi

  # Test omnictl auth
  if ! omnictl get clusters &>/dev/null; then
    error "omnictl not authenticated"
    exit 1
  fi

  if ! command -v tailscale &>/dev/null; then
    error "tailscale not found in PATH"
    exit 1
  fi

  if [ ! -x "$PROVIDER_CTL" ]; then
    error "Provider control script is not executable: $PROVIDER_CTL"
    exit 1
  fi

  for host in "${PROXMOX_HOSTS[@]}"; do
    if ! tailscale ssh "root@$host" true &>/dev/null; then
      error "Cannot reach Proxmox host over Tailscale SSH: $host"
      exit 1
    fi
  done

  log "Prerequisites OK"
}

# Count Talos VMs across all Proxmox hosts
count_talos_vms() {
  local count=0
  for host in "${PROXMOX_HOSTS[@]}"; do
    local host_count
    local vm_json

    if ! vm_json=$(tailscale ssh "root@$host" \
      "pvesh get /nodes/$host/qemu --output-format json"); then
      return 1
    fi

    host_count=$(jq '[.[] | select(.name | startswith("talos"))] | length' <<<"$vm_json")
    count=$((count + host_count))
  done
  echo "$count"
}

# Phase 3: Destroy cluster
phase_destroy() {
  log "=== Phase 3: Destroy Cluster ==="

  # Check if cluster exists
  if ! omnictl get cluster "$CLUSTER_NAME" &>/dev/null; then
    warn "Cluster $CLUSTER_NAME does not exist, skipping destruction"
    return 0
  fi

  log "Deleting cluster $CLUSTER_NAME..."
  omnictl cluster delete "$CLUSTER_NAME"

  poll_until \
    "All Talos VMs destroyed" \
    'test "$(count_talos_vms)" -eq 0' \
    "$TIMEOUT_VM_DESTROY" \
    'for h in "${PROXMOX_HOSTS[@]}"; do echo "=== $h ==="; tailscale ssh "root@$h" "pvesh get /nodes/$h/qemu --output-format json" | jq -r ".[] | select(.name | startswith(\"talos\")) | .name" || true; done'

  record_phase_time "destroy"
  log "Cluster destroyed"
}

# Phase 4: Recreate cluster
phase_recreate() {
  log "=== Phase 4: Recreate Cluster ==="

  log "Applying cluster template..."
  omnictl cluster template sync -f "$CLUSTER_TEMPLATE"

  poll_until \
    "All machines running" \
    'omnictl get machines -l "omni.sidero.dev/cluster=$CLUSTER_NAME" -o json 2>/dev/null | jq -e "length == $EXPECTED_MACHINES and all(.[]; .spec.phase == \"running\")" > /dev/null' \
    "$TIMEOUT_MACHINES_READY" \
    'omnictl get machines -l "omni.sidero.dev/cluster=$CLUSTER_NAME"; echo "--- Provider logs ---"; "$PROVIDER_CTL" --logs 50 || echo "Could not fetch provider logs"'

  record_phase_time "recreate"
  log "All machines running"
}

# Phase 5: Verify cluster health
phase_verify() {
  log "=== Phase 5: Verify Cluster Health ==="

  poll_until \
    "Kubernetes API available" \
    'omnictl kubeconfig "$CLUSTER_NAME" --merge > /dev/null 2>&1' \
    "$TIMEOUT_API_READY" \
    'omnictl get machines -l "omni.sidero.dev/cluster=$CLUSTER_NAME"'

  # Set kubeconfig
  log "Fetching kubeconfig..."
  omnictl kubeconfig "$CLUSTER_NAME" --merge
  kubectl config use-context "omni-$CLUSTER_NAME"

  poll_until \
    "All nodes Ready" \
    'kubectl get nodes -o json 2>/dev/null | jq -e ".items | length == $EXPECTED_MACHINES and all(.[]; any(.status.conditions[]; .type == \"Ready\" and .status == \"True\"))" > /dev/null' \
    "$TIMEOUT_NODES_READY" \
    'kubectl get nodes -o wide; kubectl describe nodes | grep -A10 "Conditions:"'

  record_phase_time "verify"
  log "Cluster healthy"
}

# Phase 6: Bootstrap GitOps
phase_bootstrap() {
  log "=== Phase 6: Bootstrap GitOps ==="

  # Check for external-secrets namespace and secret
  if ! kubectl get namespace external-secrets &>/dev/null; then
    log "Creating external-secrets namespace..."
    kubectl create namespace external-secrets
  fi

  if ! kubectl get secret universal-auth-credentials -n external-secrets &>/dev/null; then
    error "Missing required secret: universal-auth-credentials in external-secrets namespace"
    echo ""
    echo "Create the secret with:"
    echo "  kubectl create secret generic universal-auth-credentials \\"
    echo "    --from-literal=clientId=<INFISICAL_CLIENT_ID> \\"
    echo "    --from-literal=clientSecret=<INFISICAL_CLIENT_SECRET> \\"
    echo "    -n external-secrets"
    echo ""
    read -r -p "Press Enter after creating the secret, or Ctrl+C to abort: "

    if ! kubectl get secret universal-auth-credentials -n external-secrets &>/dev/null; then
      error "Secret still not found, aborting"
      exit 1
    fi
  fi

  log "Applying GitOps bootstrap..."
  kubectl apply -f "$GITOPS_BOOTSTRAP"

  poll_until \
    "ArgoCD server available" \
    'kubectl get deploy argocd-server -n argocd -o jsonpath="{.status.availableReplicas}" 2>/dev/null | grep -q "[1-9]"' \
    "$TIMEOUT_ARGOCD_READY" \
    'kubectl get pods -n argocd; kubectl get events -n argocd --sort-by=.lastTimestamp | tail -20'

  poll_until \
    "All ArgoCD apps healthy (excluding argocd-ha)" \
    'kubectl get applications -n argocd -o json 2>/dev/null | jq -e ".items | length > 0 and all(.[]; .metadata.name == \"argocd-ha\" or (.status.sync.status == \"Synced\" and .status.health.status == \"Healthy\"))" > /dev/null' \
    "$TIMEOUT_APPS_SYNCED" \
    'kubectl get applications -n argocd -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"'

  record_phase_time "bootstrap"
  log "GitOps bootstrap complete"
}

# Print summary
print_summary() {
  local end_time
  end_time=$(date +%s)
  local total_time=$((end_time - START_TIME))

  echo ""
  echo "=========================================="
  echo "       DR Recovery Complete"
  echo "=========================================="
  echo ""
  echo "Cluster: $CLUSTER_NAME"
  echo "Total time: $((total_time / 60))m $((total_time % 60))s"
  echo ""
  echo "Phase timing:"
  for phase in destroy recreate verify bootstrap; do
    if [ -n "${PHASE_TIMES[$phase]:-}" ]; then
      echo "  $phase: ${PHASE_TIMES[$phase]}s cumulative"
    fi
  done
  echo ""
  echo "Cluster status:"
  kubectl get nodes
  echo ""
  echo "ArgoCD apps:"
  kubectl get applications -n argocd -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"
  echo ""
  echo "NOTE: argocd-ha requires manual sync if HA is desired"
  echo "      Run: kubectl -n argocd patch application argocd-ha --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{}}}'"
  echo ""
}

# Main
main() {
  echo ""
  echo "=========================================="
  echo "    Omni-Scale Disaster Recovery"
  echo "=========================================="
  echo ""
  echo "This will DESTROY cluster: $CLUSTER_NAME"
  echo "All workloads and data will be lost."
  echo ""
  echo "Expected time: 30-45 minutes"
  echo "Cluster template: $CLUSTER_TEMPLATE"
  echo "GitOps bootstrap: $GITOPS_BOOTSTRAP"
  echo "Expected machines: $EXPECTED_MACHINES"
  echo "Provider diagnostics: $PROVIDER_CTL"
  echo ""
  read -r -p "Type 'yes' to continue: " confirm

  if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi

  echo ""

  check_prerequisites
  phase_destroy
  phase_recreate
  phase_verify
  phase_bootstrap
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
