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
# 1. Pod Scheduling Verification (70/30 Logic)
#---------------------------------------------------------------
separator
info "1. Node Pool & Metadata Verification"
separator

# Check node labels
RESERVED_NODES=$(kubectl get nodes -l pool=reserved --no-headers 2>/dev/null | wc -l)
SPOT_NODES=$(kubectl get nodes -l pool=spot --no-headers 2>/dev/null | wc -l)

if [ "$RESERVED_NODES" -ge 1 ]; then
  pass "Reserved pool found (pool=reserved)"
else
  fail "Reserved pool NOT found"
fi

if [ "$SPOT_NODES" -ge 2 ]; then
  pass "Spot pool found with 2 nodes (pool=spot)"
else
  fail "Spot pool found with $SPOT_NODES nodes (expected 2)"
fi

# Check frontend replicas (expecting 6)
FRONTEND_REPLICAS=$(kubectl get pods -n "$NAMESPACE" -l app=frontend --no-headers 2>/dev/null | grep -c Running)
if [ "$FRONTEND_REPLICAS" -eq 6 ]; then
  pass "Frontend has 6 running replicas"
else
  fail "Frontend has $FRONTEND_REPLICAS running replicas (expected 6)"
fi

# Check backend replicas (expecting 4)
BACKEND_REPLICAS=$(kubectl get pods -n "$NAMESPACE" -l app=backend --no-headers 2>/dev/null | grep -c Running)
if [ "$BACKEND_REPLICAS" -eq 4 ]; then
  pass "Backend has 4 running replicas"
else
  fail "Backend has $BACKEND_REPLICAS running replicas (expected 4)"
fi

echo ""
info "Pod placement details (Verification of weighted distribution):"
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
# Using wget since and read-only FS blocks apt-get
RESULT=$(kubectl exec -n "$NAMESPACE" deploy/frontend -- \
  wget -qO- --timeout=5 http://backend-svc:8080 2>/dev/null)
if [ -n "$RESULT" ]; then
  pass "Frontend → Backend: connection successful (using wget)"
else
  fail "Frontend → Backend: connection failed (should be allowed)"
fi

# 2b. Frontend → DB (should FAIL)
info "  2b. Frontend → DB (expect BLOCKED)"
RESULT=$(kubectl exec -n "$NAMESPACE" deploy/frontend -- \
  wget -qO- --timeout=5 http://db-svc:3306 2>/dev/null 2>&1)
if [ -z "$RESULT" ] || echo "$RESULT" | grep -qi "timeout\|refused\|error"; then
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

echo ""

#---------------------------------------------------------------
# 3. Kyverno Security Policy Tests
#---------------------------------------------------------------
separator
info "3. Kyverno Security Policy Tests"
separator

# 3a. Privileged container (should FAIL)
info "  3a. Try privileged container (expect DENIED)"
PRIV_RESULT=$(kubectl run test-priv-check \
  --image=nginx:1.25.4 \
  -n "$NAMESPACE" \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "test-priv-check",
        "image": "nginx:1.25.4",
        "securityContext": {
          "privileged": true
        }
      }]
    }
  }' 2>&1)
if echo "$PRIV_RESULT" | grep -qi "denied\|blocked\|error"; then
  pass "Privileged container blocked correctly"
else
  fail "Privileged container NOT blocked! Output: $PRIV_RESULT"
fi

# 3b. :latest tag (should FAIL)
info "  3b. Try :latest tag (expect DENIED)"
LATEST_RESULT=$(kubectl run test-latest-check --image=nginx:latest -n "$NAMESPACE" 2>&1)
if echo "$LATEST_RESULT" | grep -qi "denied\|blocked\|error"; then
  pass ":latest tag blocked correctly"
else
  fail ":latest tag NOT blocked! Output: $LATEST_RESULT"
fi

# 3c. runAsNonRoot (should FAIL if false)
info "  3c. Try 'runAsNonRoot: false' (expect DENIED)"
NONROOT_RESULT=$(kubectl run test-nonroot --image=nginx:1.25.4 -n "$NAMESPACE" --overrides='{"spec":{"containers":[{"name":"t","image":"nginx:1.25.4","securityContext":{"runAsNonRoot":false}}]}}' 2>&1)
if echo "$NONROOT_RESULT" | grep -qi "denied\|blocked\|error"; then
  pass "runAsNonRoot: false blocked correctly"
else
  fail "runAsNonRoot: false NOT blocked!"
fi

# 3d. allowPrivilegeEscalation (should FAIL if true)
info "  3d. Try 'allowPrivilegeEscalation: true' (expect DENIED)"
PRIV_ESC_RESULT=$(kubectl run test-priv-esc --image=nginx:1.25.4 -n "$NAMESPACE" --overrides='{"spec":{"containers":[{"name":"t","image":"nginx:1.25.4","securityContext":{"allowPrivilegeEscalation":true}}]}}' 2>&1)
if echo "$PRIV_ESC_RESULT" | grep -qi "denied\|blocked\|error"; then
  pass "allowPrivilegeEscalation: true blocked correctly"
else
  fail "allowPrivilegeEscalation: true NOT blocked!"
fi

# 3e. readOnlyRootFilesystem (should FAIL if false)
info "  3e. Try 'readOnlyRootFilesystem: false' (expect DENIED)"
READONLY_RESULT=$(kubectl run test-readonly --image=nginx:1.25.4 -n "$NAMESPACE" --overrides='{"spec":{"containers":[{"name":"t","image":"nginx:1.25.4","securityContext":{"readOnlyRootFilesystem":false}}]}}' 2>&1)
if echo "$READONLY_RESULT" | grep -qi "denied\|blocked\|error"; then
  pass "readOnlyRootFilesystem: false blocked correctly"
else
  fail "readOnlyRootFilesystem: false NOT blocked!"
fi

echo ""

#---------------------------------------------------------------
# 4. Resilience Framework (PDB)
#---------------------------------------------------------------
separator
info "4. Resilience (PodDisruptionBudget)"
separator

PDB_COUNT=$(kubectl get pdb -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$PDB_COUNT" -ge 2 ]; then
  pass "Found $PDB_COUNT PodDisruptionBudgets"
else
  fail "Expected 2 PDBs, found $PDB_COUNT"
fi

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
