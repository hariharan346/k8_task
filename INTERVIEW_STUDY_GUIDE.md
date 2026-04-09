# 🎓 Interview Preparation & Project Deep-Dive

This document is your "Cheat Sheet" for explaining this project in a professional interview. It covers the **Why**, the **How**, and the **Code** behind every technical decision.

---

## 1. The High-Level Pitch
> **"I built a production-grade Kubernetes environment that simulates a modern cloud topology with heterogeneous node pools (Spot & Reserved). The project focuses on cost-optimization, zero-trust security, and high availability using a 3-tier application stack."**

---

## 2. Architecture & Design Decisions

### **Heterogeneous Node Pools**
- **The Concept:** We divided the worker nodes into two pools: `Reserved` (for stable, baseline load) and `Spot` (for cheap, ephemeral, scalable load).
- **The Code (`cluster-setup.sh`):**
  ```bash
  kubectl label node agent-0 pool=reserved
  kubectl label node agent-1 pool=spot
  kubectl label node agent-2 pool=spot
  ```

### **The "70/30" Scheduling Logic**
- **Challenge:** How do you tell Kubernetes to put 70% of load on Spot and 30% on Reserved?
- **Solution:** **Weighted Node Affinity**.
- **Code Explained (`frontend/deployment.yaml`):**
  ```yaml
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 70
        preference: { matchExpressions: [{ key: pool, operator: In, values: [spot] }] }
      - weight: 30
        preference: { matchExpressions: [{ key: pool, operator: In, values: [reserved] }] }
  ```
- **Why `preferred`?** If we used `required`, and Spot nodes went down, the pods would stay `Pending` (Downtime). Using `preferred` allows the pods to failover to the Reserved pool if necessary.

---

## 3. Zero-Trust Security Model

### **Network Isolation**
- **Concept:** By default, internal traffic is blocked. Only "Business Logic" paths are open.
- **Code Explained (`policies/network-policy.yaml`):**
  1. `default-deny-all`: Blocks everything.
  2. `frontend-to-backend`: Only allows the frontend namespace to talk to the backend on port 8080.
  3. `backend-to-db`: Only allows the backend to talk to the database on port 3306.
- **Interview Answer:** *"I implemented a Layer 4 security boundary where even if a pod is compromised, the attacker cannot scan the internal network because of the default-deny policies."*

### **Policy Enforcement (Kyverno)**
- **Concept:** We use an Admission Controller to stop insecure pods *before* they are created.
- **Code Explained (`policies/kyverno-policies.yaml`):**
  - **Disallow Privileged:** Prevents containers from getting root-level host access.
  - **Disallow Latest Tag:** Enforces version pinning (immutability).

---

## 4. Resilience & The "Chaos" Story

### **Pod Disruption Budgets (PDB)**
- **Concept:** Prevents too many replicas from being taken down at once during maintenance or "Spot reclamation."
- **Code Explained (`pdb/frontend-pdb.yaml`):**
  ```yaml
  minAvailable: 2
  ```
- **Interview Answer:** *"I used PDBs to ensure that even during a node drain or a spot termination event, the application maintains a minimum healthy replica count to prevent customer-facing downtime."*

### **The Descheduler (Rebalancing)**
- **Concept:** The native Kubernetes scheduler is "static" (it never moves pods once they are running).
- **The Problem:** If Spot nodes come back online, pods stay on the expensive Reserved nodes.
- **The Solution:** The **Kubernetes Descheduler** identifies pods violating our "70/30" preference and evicts them so they can be rescheduled onto the cheaper Spot nodes.

---

## 5. Master the Commands

| Command | Why it matters in an interview |
| :--- | :--- |
| `kubectl get nodes --show-labels` | Shows you understand node metadata and pool segregation. |
| `kubectl get pods -o wide` | Proves your scheduling logic (Affinities) actually worked by showing the `NODE` column. |
| `kubectl drain <node>` | Demonstrates your knowledge of maintenance windows and pod eviction logic. |
| `kubectl rollout status` | Shows you understand how to verify the success of a deployment programmatically. |

---

## 6. Likely Interview Questions

**Q: Why did you use k3d instead of Minikube?**
*A: k3d is container-based and extremely fast. It allows me to create multi-node clusters in seconds, which is essential for testing scheduling constraints like Affinity and Topology Spread.*

**Q: How do you handle database security?**
*A: Beyond the Network Policy, I isolated the database in its own tier and ensured it has no egress (outbound) traffic allowed, preventing data exfiltration.*

**Q: What happens if a node fails?**
*A: The ReplicaSet controller detects the missing pods, and the scheduler recreates them on other nodes. Because I used `topologySpreadConstraints`, the pods should stay distributed instead of all landing on a single node.*
