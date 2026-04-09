# 🛠️ Operations & Command Guide

This guide provides a deep-dive into every command used in this project, explaining **what** it does, **how** it works, and **why** it is used.

---

## 🚀 Phase 1: Infrastructure Setup

### 1. `./cluster-setup.sh`
**Purpose:** Automates the complete creation and configuration of the local environment.

**What happens inside:**
1. **Prerequisite Check:** Verifies `docker`, `k3d`, `kubectl`, and `helm` are installed.
2. **Cluster Creation:** Runs `k3d cluster create`. This spins up a lightweight Kubernetes distribution (K3s) inside Docker containers.
   - `k3d` uses Docker containers as "nodes". 
   - It sets up a dedicated network and manages the API server access.
3. **Node Labeling:** Uses `kubectl label node`. This is crucial for our scheduling strategy.
   - We assign `pool=reserved` and `pool=spot` to specific nodes to mimic cloud instance types.
4. **Manifest Deployment:** Applies all YAML files in order (namespaces, deployments, services, policies).
5. **Helm Installations:** Installs **Kyverno** (Policy Engine) and **Descheduler**.
6. **Readiness Polling:** Loops until all pods are `Ready` using `kubectl rollout status` and custom polling.

---

## 🧪 Phase 2: Results & Validation

### 2. `./tests/validate.sh`
**Purpose:** Automated validation of the entire project state.

**Tests performed:**
- **Node Labels:** Checks if `pool=reserved` and `pool=spot` exist.
- **Pod Placement:** Verifies if frontend/backend pods landed on the correct pools.
- **Network Policies:** 
  - Tries to `curl` backend from frontend (Success expected).
  - Tries to `curl` DB from frontend (Failure expected).
- **Security Policies:**
  - Tries to launch a privileged container (Should be REJECTED).
  - Tries to launch a container with the `:latest` tag (Should be REJECTED).

---

## 🕵️ Phase 3: Manual Command Reference

Use these commands to "show the results" manually during a demo.

### Infrastructure Observability

#### `kubectl get nodes --show-labels`
- **What:** Lists all worker nodes and their metadata.
- **Why:** To prove that we have successfully tagged nodes as `reserved` and `spot`.

#### `kubectl get pods -n three-tier -o wide`
- **What:** Lists all pods with their IP addresses and assigned nodes.
- **Why:** The `-o wide` flag is the most important; it shows exactly which "pool" each pod is running on.

---

### Demonstrating Security (Kyverno)

#### Test: Block Privileged Containers
```bash
kubectl run test-priv --image=nginx:1.25.4 -n three-tier \
  --overrides='{"spec":{"containers":[{"name":"t","image":"nginx:1.25.4","securityContext":{"privileged":true}}]}}'
```
- **What:** Attempts to bypass security by requesting root-level system access.
- **Result:** Kyverno intercepts this and says `validation error: privileged containers are not allowed`.

#### Test: Block Latest Tags
```bash
kubectl run test-latest --image=nginx:latest -n three-tier
```
- **What:** Attempts to deploy an untracked, mutable image version.
- **Result:** Blocked. We enforce strict version pinning for stability.

---

### Demonstrating Resilience (PDB & Chaos)

#### `kubectl drain <node-name> --ignore-daemonsets --force`
- **What:** Safely evicts all workloads from a node.
- **Why:** To simulate a "Spot Termination". Notice how the pods don't all die at once; the **PodDisruptionBudget** ensures at least 1-2 replicas stay online while others migrate.

#### `kubectl scale deployment frontend -n three-tier --replicas=8`
- **What:** Increases the count of frontend pods.
- **Why:** To show that new pods automatically respect the node labels and affinities.

---

## 🧹 Cleanup

### `k3d cluster delete three-tier`
- **What:** Complete destruction of the environment.
- **Why:** To free up local Docker resources after you are done with the results presentation.
