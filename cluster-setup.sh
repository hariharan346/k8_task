#!/bin/bash
set -euo pipefail

#===============================================================
# K3d 3-Tier Kubernetes Cluster Setup Script
# Creates a multi-node k3d cluster with workload isolation,
# scheduling, security policies, and resilience.
#===============================================================

CLUSTER_NAME="three-tier"
NAMESPACE="three-tier"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#---------------------------------------------------------------
# Color helpers
#---------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

#---------------------------------------------------------------
# Function: wait_for_api_server
#---------------------------------------------------------------
wait_for_api_server() {
  info "Waiting for API server to become fully responsive..."
  local timeout=120
  local elapsed=0
  local interval=2

  while [ $elapsed -lt $timeout ]; do
    if kubectl cluster-info &>/dev/null; then
      ok "API server is responsive."
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  fail "Timeout reached waiting for API server."
  exit 1
}

#---------------------------------------------------------------
# Function: wait_for_pods_ready
#---------------------------------------------------------------
wait_for_pods_ready() {
  local namespace=$1
  local timeout=${2:-300}
  local interval=2
  local elapsed=0

  info "Validating readiness for all pods in namespace '$namespace'..."

  while [ $elapsed -lt $timeout ]; do
    local pod_info
    pod_info=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null || echo "")

    if [ -z "$pod_info" ]; then
      # Wait for pods to appear
      sleep $interval
      elapsed=$((elapsed + interval))
      continue
    fi

    local total_pods=0
    local ready_pods=0
    local check_failed=0

    while read -r name ready status rests args; do
      [ -n "$name" ] || continue
      total_pods=$((total_pods + 1))

      local current=${ready%/*}
      local total=${ready#*/}

      if [[ "$status" == "Completed" ]]; then
         ready_pods=$((ready_pods + 1))
      elif [[ "$status" == "Running" ]] && [[ "$current" == "$total" ]]; then
         ready_pods=$((ready_pods + 1))
      else
         check_failed=1
      fi
    done <<< "$pod_info"

    if [ "$total_pods" -gt 0 ] && [ "$check_failed" -eq 0 ]; then
      ok "All $total_pods pods in namespace '$namespace' are ready."
      return 0
    fi

    info "Waiting... ($ready_pods/$total_pods ready in '$namespace') - elapsed ${elapsed}s / ${timeout}s"
    
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  fail "Timeout (${timeout}s) waiting for pods in '$namespace'."
  kubectl get pods -n "$namespace" || true
  exit 1
}

#---------------------------------------------------------------
# 1. Prerequisites Check
#---------------------------------------------------------------
info "Checking prerequisites..."

# Define commands (handling .exe on Windows)
K3D_CMD="k3d"
HELM_CMD="helm"
KUBECTL_CMD="kubectl"

for cmd in docker k3d kubectl helm; do
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd found: $(command -v "$cmd")"
  elif command -v "$cmd.exe" &>/dev/null; then
    ok "$cmd.exe found: $(command -v "$cmd.exe")"
    case $cmd in
      k3d) K3D_CMD="k3d.exe" ;;
      helm) HELM_CMD="helm.exe" ;;
      kubectl) KUBECTL_CMD="kubectl.exe" ;;
    esac
  else
    fail "$cmd is not installed. Please install it first."
    exit 1
  fi
done

# Wrapper functions for cross-platform compatibility
k3d() { command "$K3D_CMD" "$@"; }
helm() { command "$HELM_CMD" "$@"; }
kubectl() { command "$KUBECTL_CMD" "$@"; }

# Ensure Docker is running
if ! docker info &>/dev/null; then
  fail "Docker daemon is not running. Please start Docker."
  exit 1
fi
ok "Docker daemon is running."

#---------------------------------------------------------------
# 2. Cluster Creation
#---------------------------------------------------------------
info "Checking if cluster '$CLUSTER_NAME' already exists..."
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  warn "Cluster '$CLUSTER_NAME' already exists. Deleting it first..."
  k3d cluster delete "$CLUSTER_NAME"
fi

info "Creating k3d cluster '$CLUSTER_NAME' with 1 server + 3 agents..."
k3d cluster create "$CLUSTER_NAME" \
  --servers 1 \
  --agents 3 \
  --api-port 127.0.0.1:6551 \
  --k3s-arg "--disable=traefik@server:*" \
  --wait

ok "Cluster '$CLUSTER_NAME' created successfully."

#---------------------------------------------------------------
# 3. Node Labeling
#---------------------------------------------------------------
wait_for_api_server

info "Labeling worker nodes..."

# Get agent node names (sorted for deterministic assignment)
AGENT_NODES=($(kubectl get nodes --no-headers -o custom-columns=":metadata.name" | grep -i agent | sort))

if [ "${#AGENT_NODES[@]}" -lt 3 ]; then
  fail "Expected at least 3 agent nodes, found ${#AGENT_NODES[@]}"
  exit 1
fi

kubectl label node "${AGENT_NODES[0]}" pool=reserved tier=frontend tier=backend tier=db --overwrite
kubectl label node "${AGENT_NODES[1]}" pool=spot     tier=frontend tier=backend        --overwrite
kubectl label node "${AGENT_NODES[2]}" pool=spot     tier=frontend tier=backend        --overwrite

ok "Node labels applied:"
kubectl get nodes --show-labels | grep -E "NAME|agent"

#---------------------------------------------------------------
# 4. Wait for Core Components
#---------------------------------------------------------------
info "Waiting for core nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

wait_for_pods_ready kube-system
ok "Core components are ready."

#---------------------------------------------------------------
# 5. Create Namespace
#---------------------------------------------------------------
info "Applying namespace..."
kubectl apply -f "$SCRIPT_DIR/namespaces.yaml"
ok "Namespace '$NAMESPACE' created."

#---------------------------------------------------------------
# 5. Deploy Application Tiers
#---------------------------------------------------------------
info "Deploying frontend..."
kubectl apply -f "$SCRIPT_DIR/frontend/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/frontend/service.yaml"

info "Deploying backend..."
kubectl apply -f "$SCRIPT_DIR/backend/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/backend/service.yaml"

info "Deploying database..."
kubectl apply -f "$SCRIPT_DIR/db/pod.yaml"

ok "All application manifests applied."

#---------------------------------------------------------------
# 6. Apply PodDisruptionBudgets
#---------------------------------------------------------------
info "Applying PodDisruptionBudgets..."
kubectl apply -f "$SCRIPT_DIR/pdb/frontend-pdb.yaml"
kubectl apply -f "$SCRIPT_DIR/pdb/backend-pdb.yaml"
ok "PDBs applied."

#---------------------------------------------------------------
# 7. Apply Network Policies
#---------------------------------------------------------------
info "Applying Network Policies..."
kubectl apply -f "$SCRIPT_DIR/policies/network-policy.yaml"
ok "Network policies applied."

#---------------------------------------------------------------
# 8. Install Kyverno + Policies
#---------------------------------------------------------------
info "Installing Kyverno via Helm..."
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo update

if helm list -n kyverno | grep -q kyverno; then
  warn "Kyverno already installed. Syncing..."
  helm upgrade kyverno kyverno/kyverno -n kyverno
else
  info "Installing Kyverno..."
  helm install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace
fi
ok "Kyverno chart applied."

wait_for_pods_ready kyverno

info "Waiting for Kyverno webhook to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=admission-controller -n kyverno --timeout=120s 2>/dev/null || \
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=kyverno -n kyverno --timeout=120s
ok "Kyverno webhook ready."

info "Applying Kyverno policies..."
kubectl apply -f "$SCRIPT_DIR/policies/kyverno-policies.yaml"
ok "Kyverno policies applied."

#---------------------------------------------------------------
# 9. Install Descheduler
#---------------------------------------------------------------
info "Installing Kubernetes Descheduler via Helm..."
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/ 2>/dev/null || true
helm repo update descheduler

if helm list -n kube-system | grep -q descheduler; then
  warn "Descheduler already installed. Syncing..."
  helm upgrade descheduler descheduler/descheduler -n kube-system -f "$SCRIPT_DIR/descheduler-values.yaml"
else
  helm install descheduler descheduler/descheduler \
    --namespace kube-system \
    -f "$SCRIPT_DIR/descheduler-values.yaml"
fi
ok "Descheduler chart applied."

wait_for_pods_ready kube-system

#---------------------------------------------------------------
# 10. Wait for Deployments
#---------------------------------------------------------------
info "Waiting for application workloads to be ready..."
# Built-in wait mechanisms for immediate events
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/backend  -n "$NAMESPACE" --timeout=120s

# Comprehensive readiness validation for the application namespace
wait_for_pods_ready "$NAMESPACE"
ok "All workloads are ready."

#---------------------------------------------------------------
# 10. Trivy Image Scan
#---------------------------------------------------------------
if command -v trivy &>/dev/null; then
  info "Trivy detected — running image vulnerability scans..."
  chmod +x "$SCRIPT_DIR/security/trivy-scan.sh"
  "$SCRIPT_DIR/security/trivy-scan.sh" || true
  ok "Trivy scans complete. Reports saved in security/reports/."
else
  warn "Trivy not installed — skipping vulnerability scan (optional)."
  info "To install: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh"
fi

#---------------------------------------------------------------
# 11. Summary
#---------------------------------------------------------------
echo ""
echo "============================================================"
echo -e "${GREEN} CLUSTER SETUP COMPLETE${NC}"
echo "============================================================"
echo ""
info "Cluster:   $CLUSTER_NAME"
info "Namespace: $NAMESPACE"
echo ""
info "Node assignments:"
for i in 0 1 2; do
  POOL=$(kubectl get node "${AGENT_NODES[$i]}" -o jsonpath='{.metadata.labels.pool}')
  echo "   ${AGENT_NODES[$i]} → pool=$POOL"
done
echo ""
info "Pod placement:"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""
info "Next steps:"
info "  1. Run automated tests:  chmod +x tests/validate.sh && ./tests/validate.sh"
info "  2. Manual test commands: tests/test-commands.md"
info "  3. Trivy scan (bonus):   chmod +x security/trivy-scan.sh && ./security/trivy-scan.sh"
echo "============================================================"

