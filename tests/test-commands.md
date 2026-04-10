# 🧪 Manual Validation & Testing Commands

Use these commands to manually verify the project's health, security, and scheduling logic. These are perfect for demonstrating "results" during an interview.

---

## 1. Node Pool & Metadata Verification

Confirm that your worker nodes have been successfully categorized into heterogeneous pools (`reserved` and `spot`).

```bash
# Check node labels
kubectl get nodes --show-labels | grep pool
```

**Expected Result:**
- `agent-0` → `pool=reserved`
- `agent-1` & `agent-2` → `pool=spot`

---

## 2. Pod Scheduling (The 70/30 Distribution)

Verify that the weighted Node Affinity and Topology Spread constraints are distributing the load correctly.

```bash
# List pods with their hosting nodes and pool labels
kubectl get pods -n three-tier -o wide --show-labels | grep -E "frontend|backend"
```

**What to explain:**
- You have **6 frontend replicas** and **4 backend replicas**.
- Based on the **70/30 distribution** strategy:
  - **Frontend (6 pods)**: Should result in **4 pods on spot** (2 per node) and **2 pods on reserved**.
  - **Backend (4 pods)**: Should result in **3 pods on spot** and **1 pod on reserved**.
- The `topologySpreadConstraints` (hostname) ensures that pods are spread evenly across all agents, preventing any single node from being overloaded.
- If you drain a spot node, these pods will automatically migrate to the `reserved` pool to maintain availability.

---

## 3. Network Policy Enforcement

### 3a. Frontend → Backend (Should SUCCEED ✅)
```bash
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "apt-get update -qq && apt-get install -y -qq curl > /dev/null 2>&1 && curl -s --max-time 5 http://backend-svc:8080"
```
**Observation:** The frontend *needs* to speak to the backend to function. This should return the backend's directory listing.

### 3b. Frontend → DB (Should be BLOCKED ❌)
```bash
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "curl -s --max-time 5 http://db-svc:3306 || echo 'SUCCESS: BLOCKED BY POLICY'"
```
**Observation:** In a secure architecture, the frontend should never talk to the DB directly. The network policy correctly drops this traffic.

### 3c. Backend → DB (Should SUCCEED ✅)
```bash
kubectl exec -n three-tier deploy/backend -- \
  sh -c "python -c \"import socket; s=socket.socket(); s.settimeout(5); s.connect(('db-svc', 3306)); print('DB CONNECTION OK'); s.close()\""
```
**Observation:** The backend contains the business logic that requires DB access. This path is whitelisted.

---

## 4. Security Enforcement (Kyverno)

### 4a. Blocking Privileged Containers
```bash
kubectl run test-priv --image=nginx:1.25.4 -n three-tier \
  --overrides='{"spec":{"containers":[{"name":"t","image":"nginx:1.25.4","securityContext":{"privileged":true}}]}}'
```
**Expected:** The API server will reject the request. This proves the **Admission Controller** is enforcing security baseline policies.

### 4b. Blocking `:latest` Tags
```bash
kubectl run test-latest --image=nginx:latest -n three-tier
```
**Expected:** Rejected. We enforce strict version pinning (`nginx:1.25.4`) to ensure immutability and stable deployments.

---

## 5. Resilience & Chaos (PDB)

### 5a. Verify Disruption Budgets
```bash
kubectl get pdb -n three-tier
```
**Expected:** `frontend-pdb` should show `minAvailable: 2`. This means even if you drain a node, Kubernetes will refuse to kill pods if it would drop the count below 2.

### 5b. Simulate a Node Loss (Drain)
```bash
# Identify a Spot node
NODE_TO_DRAIN=$(kubectl get nodes -l pool=spot -o jsonpath='{.items[0].metadata.name}')
echo "Simulating failure of node: $NODE_TO_DRAIN"

# Drain the node
kubectl drain "$NODE_TO_DRAIN" --ignore-daemonsets --delete-emptydir-data --force
```
**Observation:** Watch the pods in another terminal (`kubectl get pods -w`). The PDB ensures the application stays online while pods migrate to the `reserved` pool.

---

---

## 7. The Spot Node Challenge (Interview Demo)

Use these commands to perform the exact "chaos demo" requested by the reviewer: *What happens if you remove the 'spot' nodes and then create a new pod?*

### 7a. Simulate "Spot Termination" (Shut Down Node)
```bash
# Identify and stop a spot node using k3d
NODE_NAME=$(kubectl get nodes -l pool=spot -o jsonpath='{.items[0].metadata.name}')
echo "Stopping spot node: $NODE_NAME"

k3d node stop "$NODE_NAME"
```

### 7b. Observe "Resilience Fallback"
Watch how the **Hard Affinity** and **PDB** work together to keep the app online on the `reserved` pool.
```bash
# Watch pods move to the reserved node (agent-0)
kubectl get pods -n three-tier -o wide -w
```
**Explain**: "The required node affinity ensures pods only land on authorized nodes. When spot nodes are gone, the reserved pool picks up the slack automatically."

### 7c. Scale Up While Spot is Down
```bash
# Force a new pod creation by scaling up
kubectl scale deployment/frontend -n three-tier --replicas=7
```
**Explain**: "Because of our hard fallback logic, New pods correctly schedule on the 'reserved' pool even though their 'preferred' spot pool is missing."

### 7d. Restore Spot & Watch Rebalancing
```bash
# Start the node back up
k3d node start "$NODE_NAME"

# Wait ~1 minute for the Descheduler to trigger
# Watch pods move FROM reserved node TO the new spot node
kubectl get pods -n three-tier -o wide -w
```
**Explain**: "Once capacity returns, the Kubernetes Descheduler detects the topology skew and evicts pods from the reserved node to restore our desired 70/30 distribution."

---

## 8. Cleanup

To destroy the cluster and clean up all Docker resources:
```bash
k3d cluster delete three-tier
```
