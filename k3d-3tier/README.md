# K3d 3-Tier Kubernetes Environment

A production-grade local Kubernetes setup demonstrating workload isolation, high availability, security best practices, and scheduling constraints using k3d.

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    k3d Cluster: three-tier                    │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  Agent-0      │  │  Agent-1      │  │  Agent-2      │      │
│  │  tier=frontend│  │  tier=backend │  │  tier=db      │      │
│  │               │  │               │  │               │      │
│  │ ┌──────────┐  │  │ ┌──────────┐  │  │ ┌──────────┐  │     │
│  │ │ nginx    │  │  │ │ python   │  │  │ │ busybox  │  │     │
│  │ │ (x2)     │  │  │ │ http.svr │  │  │ │ (db sim) │  │     │
│  │ │          │  │  │ │ (x2)     │  │  │ │ (x1)     │  │     │
│  │ └──────────┘  │  │ └──────────┘  │  │ └──────────┘  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
│  Traffic Flow:  Frontend ──→ Backend ──→ Database            │
│  All other traffic: ██ DENIED ██                             │
└──────────────────────────────────────────────────────────────┘
```

### Components

| Tier       | Image             | Replicas | Port | Node Label     |
|------------|-------------------|----------|------|----------------|
| Frontend   | `nginx:1.25.4`    | 2        | 80   | `tier=frontend`|
| Backend    | `python:3.12-slim`| 2        | 8080 | `tier=backend` |
| Database   | `busybox:1.36`    | 1        | 3306 | `tier=db`      |

---

## 📍 Node Labeling Strategy

The cluster has **3 agent (worker) nodes**, each assigned a dedicated tier label:

```
k3d-three-tier-agent-0 → tier=frontend
k3d-three-tier-agent-1 → tier=backend
k3d-three-tier-agent-2 → tier=db
```

**Why?** This provides:
- **Workload isolation** — pods run only on designated nodes
- **Predictable placement** — critical workloads won't compete for the same resources
- **Simplified debugging** — you always know where to look

---

## 📍 Scheduling Explanation

### nodeSelector

Each deployment/pod uses `nodeSelector` to pin workloads to their designated nodes:

```yaml
nodeSelector:
  tier: frontend  # Only runs on nodes labeled tier=frontend
```

### podAntiAffinity

Frontend and backend deployments use `preferredDuringSchedulingIgnoredDuringExecution` anti-affinity to spread replicas across nodes:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values: ["frontend"]
          topologyKey: kubernetes.io/hostname
```

> **Note:** Since each tier has only 1 dedicated node, both replicas will land on the same node. The anti-affinity is configured for production readiness — if more nodes are added with the same tier label, pods will spread automatically.

---

## 🛡️ Security Explanation

### Network Policies (Zero-Trust Model)

| Policy                        | Effect                                        |
|-------------------------------|-----------------------------------------------|
| `default-deny-all`           | Block ALL ingress + egress by default          |
| `allow-dns`                  | Allow DNS resolution (port 53) for all pods    |
| `frontend-egress-to-backend` | Frontend can reach Backend on port 8080        |
| `backend-ingress-from-frontend`| Backend accepts traffic from Frontend        |
| `backend-egress-to-db`       | Backend can reach DB on port 3306              |
| `db-ingress-from-backend`    | DB accepts traffic from Backend                |

**Traffic Matrix:**

| From \ To  | Frontend | Backend | Database |
|------------|----------|---------|----------|
| Frontend   | —        | ✅       | ❌        |
| Backend    | ❌        | —       | ✅        |
| Database   | ❌        | ❌       | —        |

### Kyverno Policies

| Policy                        | Effect                                    |
|-------------------------------|-------------------------------------------|
| `disallow-privileged-containers`| Blocks `privileged: true` containers    |
| `disallow-latest-tag`        | Blocks images with `:latest` or no tag     |

---

## 🛡️ Resilience

**PodDisruptionBudgets:**

| PDB            | MinAvailable | Covers      |
|----------------|-------------|-------------|
| `frontend-pdb` | 1           | Frontend    |
| `backend-pdb`  | 1           | Backend     |

During voluntary disruptions (e.g., `kubectl drain`), the PDB ensures at least 1 pod per tier remains available.

---

## 📁 Project Structure

```
k3d-3tier/
├── cluster-setup.sh            # Main setup script
├── namespaces.yaml             # Namespace definition
├── frontend/
│   ├── deployment.yaml         # Nginx frontend (2 replicas)
│   └── service.yaml            # ClusterIP service
├── backend/
│   ├── deployment.yaml         # Python HTTP server (2 replicas)
│   └── service.yaml            # ClusterIP service
├── db/
│   └── pod.yaml                # Busybox DB simulator + service
├── policies/
│   ├── network-policy.yaml     # 6 NetworkPolicy resources
│   └── kyverno-policies.yaml   # 2 ClusterPolicy resources
├── pdb/
│   ├── frontend-pdb.yaml       # PDB for frontend
│   └── backend-pdb.yaml        # PDB for backend
├── tests/
│   └── test-commands.md        # All validation commands
└── README.md                   # This file
```

---

## 🚀 How to Run (Step-by-Step)

### Prerequisites

Install the following tools:

| Tool     | Install Command                                              |
|----------|--------------------------------------------------------------|
| Docker   | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| k3d      | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` |
| kubectl  | `curl -LO https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/` |
| Helm     | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |

### Setup

```bash
# 1. Clone or navigate to the project directory
cd k3d-3tier/

# 2. Make the script executable
chmod +x cluster-setup.sh

# 3. Run the full setup
./cluster-setup.sh
```

The script will:
1. Verify all prerequisites are installed
2. Create a k3d cluster with 1 server + 3 agents
3. Label nodes with tier designations
4. Deploy all application manifests
5. Apply PDBs and Network Policies
6. Install Kyverno and apply security policies
7. Wait for all workloads to become ready

---

## 🧪 Testing Steps

After setup completes, follow all tests in [`tests/test-commands.md`](tests/test-commands.md).

### Quick Smoke Test

```bash
# Verify all pods are running on correct nodes
kubectl get pods -n three-tier -o wide

# Test frontend → backend connectivity (should succeed)
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "apt-get update -qq && apt-get install -y -qq curl > /dev/null 2>&1 && curl -s --max-time 5 http://backend-svc:8080"

# Test frontend → db connectivity (should fail)
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "curl -s --max-time 5 http://db-svc:3306 || echo 'BLOCKED - Network Policy working!'"

# Test Kyverno: try privileged container (should be blocked)
kubectl run test-priv --image=nginx:1.25.4 -n three-tier \
  --overrides='{"spec":{"containers":[{"name":"t","image":"nginx:1.25.4","securityContext":{"privileged":true}}]}}'

# Test Kyverno: try :latest tag (should be blocked)
kubectl run test-latest --image=nginx:latest -n three-tier
```

### Full Test Suite

See [`tests/test-commands.md`](tests/test-commands.md) for the complete validation checklist with expected outputs.

---

## 🧹 Cleanup

```bash
k3d cluster delete three-tier
```

---

## 📝 Key Design Decisions

1. **Canal CNI** — k3s ships with Canal (Flannel + Calico policy), providing NetworkPolicy support without additional CNI installation.
2. **Kyverno over OPA/Gatekeeper** — Simpler YAML-native policies, no Rego language required.
3. **Preferred anti-affinity** — Uses `preferredDuringSchedulingIgnoredDuringExecution` instead of `required` because each tier has only 1 node; anti-affinity is ready to spread across multiple nodes if scaled.
4. **DNS egress policy** — Explicitly allows DNS traffic so pods can resolve service names despite the default-deny policy.
5. **Specific image tags** — All containers use pinned versions (`nginx:1.25.4`, `python:3.12-slim`, `busybox:1.36`) for reproducibility.
