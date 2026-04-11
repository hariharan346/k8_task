# 🚀 End-to-End Kubernetes Review Demo Guide

This guide provides a step-by-step script for your technical review. Each section includes a **"What to say"** part for your explanation and a **"What to run"** part with copy-pasteable commands.

---

## 📋 Phase 0: Preparation (The Clean Slate)

**What to say:** "I'll start by ensuring we have a fresh environment. My setup script handles cluster creation, node labeling, and deploying the entire 3-tier stack with security policies."

**What to run:**
```bash
# Ensure we are in the project directory
cd k8_task

# Run the full automated setup
# This creates the k3d cluster, labels nodes, installs Kyverno, Descheduler, and the App
./cluster-setup.sh
```

---

## 🏗️ Phase 1: Topology & Node Affinity

**What to say:** "We have a 4-node topology (1 Control Plane + 3 Agents). I've implemented Node Affinity to ensure pods land on specific tiers. Agent-0 is our 'Reserved' pool, while Agents 1 and 2 are our 'Spot' pool."

**What to run:**
```bash
# 1. Show nodes and their designated pools/tiers
kubectl get nodes --show-labels | grep -E "NAME|pool|tier"

# 2. Show pod placement across these tiers
kubectl get pods -n three-tier -o wide
```
*Note: You should see the DB pod on Agent-0 (Reserved) and Frontend/Backend spread across all three.*

---

## ⚖️ Phase 2: The 70/30 Split & Rebalancing (The Improvement)

**What to say:** "The requirement was a 70/30 distribution between Spot and Reserved nodes. I've achieved this using weighted Soft Node Affinity. I also installed a **Descheduler** to ensure that if nodes are lost and then return, the cluster automatically rebalances back to this 70/30 ratio."

**What to run:**
```bash
# 1. Identify a spot node to simulate a failure (e.g., agent-1)
export SPOT_NODE="k3d-three-tier-agent-1"

# 2. Drain the node (Simulate Spot termination)
kubectl drain $SPOT_NODE --ignore-daemonsets --delete-emptydir-data --force

# 3. Watch pods move to the 'Reserved' node (Agent-0)
kubectl get pods -n three-tier -o wide -w
```
*(Keyboard Interrupt `Ctrl+C` once pods are moved)*

**Now show the rebalance:**
```bash
# 4. Bring the spot node back (Simulate Spot availability)
kubectl uncordon $SPOT_NODE

# 5. Wait for the Descheduler (runs every minute) to evict pods back to the spot node
# You will see pods being 'Evicted' and 'Pending' on the new node automatically.
kubectl get pods -n three-tier -o wide -w
```

---

## 🛡️ Phase 3: Network Security (Zero Trust)

**What to say:** "I've implemented a default-deny Network Policy. We only explicitly allow talk from Frontend to Backend, and Backend to DB. Everything else is blocked."

**What to run:**
```bash
# 1. Test: Frontend -> Backend (Should be ALLOWED)
kubectl exec -n three-tier deploy/frontend -- curl -s --connect-timeout 2 http://backend-svc:8080

# 2. Test: Frontend -> DB (Should be BLOCKED)
kubectl exec -n three-tier deploy/frontend -- curl -s --connect-timeout 2 http://db-svc:3306
```

---

## 🚫 Phase 4: Policy Enforcement (Kyverno)

**What to say:** "Security isn't just network; it's also admission control. I use Kyverno cluster policies to block insecure configurations like Privileged containers or the 'latest' image tag."

**What to run:**
```bash
# 1. Attempt to deploy a pod with :latest tag (Should be DENIED)
kubectl run test-latest --image=nginx:latest -n three-tier

# 2. Attempt to deploy a Privileged container (Should be DENIED)
kubectl run test-priv --image=nginx --privileged -n three-tier
```

---

## 📉 Phase 5: Resilience (Pod Disruption Budgets)

**What to say:** "To ensure high availability during maintenance, I've applied PodDisruptionBudgets. This prevents the cluster from accidentally taking down too many replicas of a service at once."

**What to run:**
```bash
# Show the PDBs in action
kubectl get pdb -n three-tier
```

---

## ✅ Phase 6: Automated Validation Script

**What to say:** "Finally, I've built an automated test suite that programmatically verifies every requirement we've discussed today."

**What to run:**
```bash
# Run the validation suite
chmod +x tests/validate.sh
./tests/validate.sh
```

---

## 🛠️ Summary of Tools Used
*   **k3d**: For the multi-node local cluster.
*   **kubectl**: For cluster management.
*   **Helm**: For installing Kyverno and the Descheduler.
*   **Kyverno**: For Admission Control (Security Policies).
*   **Kubernetes Descheduler**: For maintaining the 70/30 topology balance.
*   **Network Policies**: For pod-level traffic isolation.
