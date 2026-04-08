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
# 1. Prerequisites Check
#---------------------------------------------------------------
info "Checking prerequisites..."

for cmd in docker k3d kubectl helm; do
  if ! command -v "$cmd" &>/dev/null; then
    fail "$cmd is not installed. Please install it first."
    exit 1
  fi
  ok "$cmd found: $(command -v "$cmd")"
done

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
  --api-port 127.0.0.1:6550 \
  --k3s-arg "--disable=traefik@server:*" \
  --wait

ok "Cluster '$CLUSTER_NAME' created successfully."

#---------------------------------------------------------------
# 3. Node Labeling
#---------------------------------------------------------------
info "Labeling worker nodes..."

# Get agent node names (sorted for deterministic assignment)
AGENT_NODES=($(kubectl get nodes --no-headers -o custom-columns=":metadata.name" | grep -i agent | sort))

if [ "${#AGENT_NODES[@]}" -lt 3 ]; then
  fail "Expected at least 3 agent nodes, found ${#AGENT_NODES[@]}"
  exit 1
fi

kubectl label node "${AGENT_NODES[0]}" tier=frontend --overwrite
kubectl label node "${AGENT_NODES[1]}" tier=backend  --overwrite
kubectl label node "${AGENT_NODES[2]}" tier=db       --overwrite

ok "Node labels applied:"
kubectl get nodes --show-labels | grep -E "NAME|agent"

#---------------------------------------------------------------
# 4. Create Namespace
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
  warn "Kyverno is already installed. Upgrading..."
  helm upgrade kyverno kyverno/kyverno -n kyverno --wait
else
  helm install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace \
    --wait
fi
ok "Kyverno installed."

info "Waiting for Kyverno webhook to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=admission-controller -n kyverno --timeout=120s 2>/dev/null || \
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=kyverno -n kyverno --timeout=120s
ok "Kyverno webhook ready."

info "Applying Kyverno policies..."
kubectl apply -f "$SCRIPT_DIR/policies/kyverno-policies.yaml"
ok "Kyverno policies applied."

#---------------------------------------------------------------
# 9. Wait for Deployments
#---------------------------------------------------------------
info "Waiting for deployments to be ready..."
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/backend  -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=Ready pod -l app=db -n "$NAMESPACE" --timeout=120s
ok "All workloads are ready."

#---------------------------------------------------------------
# 10. (BONUS) Trivy Image Scan
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
  TIER=$(kubectl get node "${AGENT_NODES[$i]}" -o jsonpath='{.metadata.labels.tier}')
  echo "   ${AGENT_NODES[$i]} → tier=$TIER"
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

