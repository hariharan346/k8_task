#!/bin/bash
set -uo pipefail

#===============================================================
# Automated Validation Script for K3d 3-Tier Environment
# Runs all tests and reports PASS/FAIL for each requirement.
#===============================================================

NAMESPACE="three-tier"
PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $*"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }
info() { echo -e "${CYAN}[TEST]${NC} $*"; }
separator() { echo "------------------------------------------------------------"; }

echo ""
echo "============================================================"
echo -e "${CYAN}  K3d 3-Tier Validation Suite${NC}"
echo "============================================================"
echo ""

#---------------------------------------------------------------
# 1. Pod Scheduling Verification
#---------------------------------------------------------------
separator
info "1. Pod Scheduling — pods on correct nodes"
separator

# Get node names by tier label
FRONTEND_NODE=$(kubectl get nodes -l tier=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
BACKEND_NODE=$(kubectl get nodes -l tier=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
DB_NODE=$(kubectl get nodes -l tier=db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# Check frontend pods
FRONTEND_PODS_ON_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=frontend -o jsonpath='{.items[*].spec.nodeName}' 2>/dev/null)
if echo "$FRONTEND_PODS_ON_NODE" | grep -q "$FRONTEND_NODE"; then
  pass "Frontend pods scheduled on tier=frontend node ($FRONTEND_NODE)"
else
  fail "Frontend pods NOT on correct node. Expected: $FRONTEND_NODE, Got: $FRONTEND_PODS_ON_NODE"
fi

# Check backend pods
BACKEND_PODS_ON_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=backend -o jsonpath='{.items[*].spec.nodeName}' 2>/dev/null)
if echo "$BACKEND_PODS_ON_NODE" | grep -q "$BACKEND_NODE"; then
  pass "Backend pods scheduled on tier=backend node ($BACKEND_NODE)"
else
  fail "Backend pods NOT on correct node. Expected: $BACKEND_NODE, Got: $BACKEND_PODS_ON_NODE"
fi

# Check db pod
DB_POD_ON_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=db -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
if [ "$DB_POD_ON_NODE" = "$DB_NODE" ]; then
  pass "DB pod scheduled on tier=db node ($DB_NODE)"
else
  fail "DB pod NOT on correct node. Expected: $DB_NODE, Got: $DB_POD_ON_NODE"
fi

# Check replica counts
FRONTEND_REPLICAS=$(kubectl get pods -n "$NAMESPACE" -l app=frontend --no-headers 2>/dev/null | grep -c Running)
if [ "$FRONTEND_REPLICAS" -ge 2 ]; then
  pass "Frontend has $FRONTEND_REPLICAS running replicas (expected: 2)"
else
  fail "Frontend only has $FRONTEND_REPLICAS running replicas (expected: 2)"
fi

BACKEND_REPLICAS=$(kubectl get pods -n "$NAMESPACE" -l app=backend --no-headers 2>/dev/null | grep -c Running)
if [ "$BACKEND_REPLICAS" -ge 2 ]; then
  pass "Backend has $BACKEND_REPLICAS running replicas (expected: 2)"
else
  fail "Backend only has $BACKEND_REPLICAS running replicas (expected: 2)"
fi

echo ""
info "Pod placement details:"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""

#---------------------------------------------------------------
# 2. Network Policy Tests
#---------------------------------------------------------------
separator
info "2. Network Policy Tests"
separator

# 2a. Frontend → Backend (should SUCCEED)
info "  2a. Frontend → Backend (expect SUCCESS)"
RESULT=$(kubectl exec -n "$NAMESPACE" deploy/frontend -- \
  sh -c "apt-get update -qq > /dev/null 2>&1; apt-get install -y -qq curl > /dev/null 2>&1; curl -s --max-time 5 http://backend-svc:8080" 2>/dev/null)
if [ -n "$RESULT" ]; then
  pass "Frontend → Backend: connection successful"
else
  fail "Frontend → Backend: connection failed (should be allowed)"
fi

# 2b. Frontend → DB (should FAIL)
info "  2b. Frontend → DB (expect BLOCKED)"
RESULT=$(kubectl exec -n "$NAMESPACE" deploy/frontend -- \
  sh -c "curl -s --max-time 5 http://db-svc:3306" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "Frontend → DB: connection blocked (network policy working)"
else
  fail "Frontend → DB: connection succeeded (should be blocked!)"
fi

# 2c. Backend → DB (should SUCCEED)
info "  2c. Backend → DB (expect SUCCESS)"
RESULT=$(kubectl exec -n "$NAMESPACE" deploy/backend -- \
  python -c "
import socket
try:
    s = socket.socket()
    s.settimeout(5)
    s.connect(('db-svc', 3306))
    print('DB OK')
    s.close()
except Exception as e:
    print(f'FAILED: {e}')
" 2>/dev/null)
if echo "$RESULT" | grep -q "DB OK"; then
  pass "Backend → DB: connection successful"
else
  fail "Backend → DB: connection failed (should be allowed). Got: $RESULT"
fi

# 2d. DB → Frontend (should FAIL)
info "  2d. DB → Frontend (expect BLOCKED)"
RESULT=$(kubectl exec -n "$NAMESPACE" db -- \
  sh -c "wget -qO- --timeout=3 http://frontend-svc:80 2>/dev/null" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "DB → Frontend: connection blocked (network policy working)"
else
  fail "DB → Frontend: connection succeeded (should be blocked!)"
fi

echo ""

#---------------------------------------------------------------
# 3. Kyverno Security Policy Tests
#---------------------------------------------------------------
separator
info "3. Kyverno Security Policy Tests"
separator

# 3a. Privileged container (should FAIL)
info "  3a. Deploy privileged container (expect DENIED)"
PRIV_RESULT=$(kubectl run test-privileged-validate \
  --image=nginx:1.25.4 \
  -n "$NAMESPACE" \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "test-privileged-validate",
        "image": "nginx:1.25.4",
        "securityContext": {
          "privileged": true
        }
      }]
    }
  }' 2>&1)
if echo "$PRIV_RESULT" | grep -qi "blocked\|denied\|failed\|error"; then
  pass "Privileged container blocked by Kyverno"
else
  fail "Privileged container was NOT blocked! Output: $PRIV_RESULT"
  kubectl delete pod test-privileged-validate -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1
fi

# 3b. :latest tag (should FAIL)
info "  3b. Deploy image with :latest tag (expect DENIED)"
LATEST_RESULT=$(kubectl run test-latest-validate \
  --image=nginx:latest \
  -n "$NAMESPACE" 2>&1)
if echo "$LATEST_RESULT" | grep -qi "blocked\|denied\|failed\|error"; then
  pass ":latest tag blocked by Kyverno"
else
  fail ":latest tag was NOT blocked! Output: $LATEST_RESULT"
  kubectl delete pod test-latest-validate -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1
fi

# 3c. No tag at all (should FAIL)
info "  3c. Deploy image with no tag (expect DENIED)"
NOTAG_RESULT=$(kubectl run test-notag-validate \
  --image=nginx \
  -n "$NAMESPACE" 2>&1)
if echo "$NOTAG_RESULT" | grep -qi "blocked\|denied\|failed\|error"; then
  pass "Image with no tag blocked by Kyverno"
else
  fail "Image with no tag was NOT blocked! Output: $NOTAG_RESULT"
  kubectl delete pod test-notag-validate -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1
fi

echo ""

#---------------------------------------------------------------
# 4. PDB & Resource Tests
#---------------------------------------------------------------
separator
info "4. PDB & Resource Verification"
separator

# Check PDB exists
PDB_COUNT=$(kubectl get pdb -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$PDB_COUNT" -ge 2 ]; then
  pass "Found $PDB_COUNT PodDisruptionBudgets"
else
  fail "Expected at least 2 PDBs, found $PDB_COUNT"
fi

# Check frontend PDB
FRONTEND_PDB_MIN=$(kubectl get pdb frontend-pdb -n "$NAMESPACE" -o jsonpath='{.spec.minAvailable}' 2>/dev/null)
if [ "$FRONTEND_PDB_MIN" = "1" ]; then
  pass "Frontend PDB minAvailable=1"
else
  fail "Frontend PDB minAvailable=$FRONTEND_PDB_MIN (expected 1)"
fi

# Check backend PDB
BACKEND_PDB_MIN=$(kubectl get pdb backend-pdb -n "$NAMESPACE" -o jsonpath='{.spec.minAvailable}' 2>/dev/null)
if [ "$BACKEND_PDB_MIN" = "1" ]; then
  pass "Backend PDB minAvailable=1"
else
  fail "Backend PDB minAvailable=$BACKEND_PDB_MIN (expected 1)"
fi

# Check resource limits on all pods
info "  Checking resource requests/limits on all pods..."
ALL_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
for POD in $ALL_PODS; do
  RESOURCES=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources}' 2>/dev/null)
  if echo "$RESOURCES" | grep -q "limits" && echo "$RESOURCES" | grep -q "requests"; then
    pass "Pod $POD has resource requests and limits"
  else
    fail "Pod $POD is MISSING resource requests/limits"
  fi
done

echo ""

#---------------------------------------------------------------
# 5. Node Labels Verification
#---------------------------------------------------------------
separator
info "5. Node Labels"
separator

for TIER in frontend backend db; do
  LABELED=$(kubectl get nodes -l "tier=$TIER" --no-headers 2>/dev/null | wc -l)
  if [ "$LABELED" -ge 1 ]; then
    NODE_NAME=$(kubectl get nodes -l "tier=$TIER" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    pass "Node labeled tier=$TIER: $NODE_NAME"
  else
    fail "No node found with label tier=$TIER"
  fi
done

echo ""

#---------------------------------------------------------------
# 6. Network Policy Count
#---------------------------------------------------------------
separator
info "6. Network Policies"
separator

NP_COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$NP_COUNT" -ge 6 ]; then
  pass "Found $NP_COUNT NetworkPolicies (expected >= 6)"
else
  fail "Found only $NP_COUNT NetworkPolicies (expected >= 6)"
fi

echo ""
info "Network policies:"
kubectl get networkpolicy -n "$NAMESPACE"
echo ""

#---------------------------------------------------------------
# Summary
#---------------------------------------------------------------
echo ""
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}  ALL TESTS PASSED: $PASS/$TOTAL${NC}"
else
  echo -e "${RED}  RESULTS: $PASS passed, $FAIL failed (out of $TOTAL)${NC}"
fi
echo "============================================================"
echo ""

exit $FAIL
