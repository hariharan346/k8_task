# 🧪 Validation & Testing Commands

All commands assume the cluster is running and manifests are applied via `cluster-setup.sh`.

---

## 1. Pod Scheduling Verification

Verify each pod is scheduled on the correctly-labeled node.

```bash
kubectl get pods -n three-tier -o wide
```

**Expected Output:**

| Pod               | Node (tier label)        |
|-------------------|--------------------------|
| frontend-xxxxx    | k3d-three-tier-agent-0 (tier=frontend) |
| frontend-xxxxx    | k3d-three-tier-agent-0 (tier=frontend) |
| backend-xxxxx     | k3d-three-tier-agent-1 (tier=backend)  |
| backend-xxxxx     | k3d-three-tier-agent-1 (tier=backend)  |
| db                | k3d-three-tier-agent-2 (tier=db)       |

Confirm with labels:

```bash
kubectl get nodes --show-labels | grep tier
```

---

## 2. Network Policy Tests

### 2a. Frontend → Backend (SHOULD SUCCEED ✅)

```bash
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "apt-get update -qq && apt-get install -y -qq curl > /dev/null 2>&1 && curl -s --max-time 5 http://backend-svc:8080"
```

**Expected:** Returns HTML directory listing (Python http.server response).

### 2b. Frontend → DB (SHOULD FAIL ❌)

```bash
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "curl -s --max-time 5 http://db-svc:3306 || echo 'CONNECTION BLOCKED'"
```

**Expected:** `CONNECTION BLOCKED` or timeout — network policy denies this path.

### 2c. Backend → DB (SHOULD SUCCEED ✅)

```bash
kubectl exec -n three-tier deploy/backend -- \
  sh -c "python -c \"import socket; s=socket.socket(); s.settimeout(5); s.connect(('db-svc', 3306)); print('DB OK'); s.close()\""
```

**Expected:** `DB OK`

### 2d. DB → Frontend (SHOULD FAIL ❌)

```bash
kubectl exec -n three-tier db -- \
  sh -c "wget -qO- --timeout=3 http://frontend-svc:80 || echo 'CONNECTION BLOCKED'"
```

**Expected:** `CONNECTION BLOCKED` — no egress policy for db pods to frontend.

---

## 3. Security Policy Tests (Kyverno)

### 3a. Try to Deploy a Privileged Container (SHOULD FAIL ❌)

```bash
kubectl run test-privileged \
  --image=nginx:1.25.4 \
  -n three-tier \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "test-privileged",
        "image": "nginx:1.25.4",
        "securityContext": {
          "privileged": true
        }
      }]
    }
  }'
```

**Expected:** Error message from Kyverno:
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
resource Pod/three-tier/test-privileged was blocked due to the following policies:
disallow-privileged-containers: deny-privileged: Privileged containers are not allowed.
```

### 3b. Try to Deploy an Image with `:latest` Tag (SHOULD FAIL ❌)

```bash
kubectl run test-latest --image=nginx:latest -n three-tier
```

**Expected:** Error message from Kyverno:
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
resource Pod/three-tier/test-latest was blocked due to the following policies:
disallow-latest-tag: deny-latest-tag: Using ':latest' tag is not allowed.
```

### 3c. Try to Deploy an Image with No Tag (SHOULD FAIL ❌)

```bash
kubectl run test-notag --image=nginx -n three-tier
```

**Expected:** Error message from Kyverno:
```
Error from server: ...
disallow-latest-tag: require-image-tag: An image tag is required. ':latest' is not allowed.
```

---

## 4. PDB & Node Drain Test

### 4a. Check PDB Status

```bash
kubectl get pdb -n three-tier
```

**Expected:**

| Name          | Min Available | Allowed Disruptions |
|---------------|---------------|---------------------|
| frontend-pdb  | 1             | 1                   |
| backend-pdb   | 1             | 1                   |

### 4b. Drain the Frontend Node

```bash
# Identify the frontend node
FRONTEND_NODE=$(kubectl get nodes -l tier=frontend -o jsonpath='{.items[0].metadata.name}')
echo "Draining node: $FRONTEND_NODE"

# Drain the node (frontend pods must reschedule; PDB protects availability)
kubectl drain "$FRONTEND_NODE" --ignore-daemonsets --delete-emptydir-data
```

**Expected Behavior:**
- Because `minAvailable: 1` and there are 2 replicas, the drain can evict 1 pod at a time.
- If all 2 replicas are on the same node (only 1 frontend node), the PDB will allow eviction
  of 1, but the second pod cannot be placed until a suitable node exists.
- The PDB prevents the last available pod from being evicted simultaneously.

### 4c. Verify Pods After Drain

```bash
kubectl get pods -n three-tier -o wide
```

**Expected:** Frontend pods will be in `Pending` state (no other `tier=frontend` node available).

### 4d. Uncordon the Node

```bash
kubectl uncordon "$FRONTEND_NODE"
```

```bash
# Wait a few seconds, then verify pods are running again
kubectl get pods -n three-tier -o wide
```

**Expected:** All pods return to `Running` state.

---

## 5. Resource Limits Verification

```bash
kubectl get pods -n three-tier -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources}{"\n"}{end}'
```

**Expected:** Every pod should have `requests` and `limits` for both `cpu` and `memory`.

---

## 6. Cleanup

```bash
k3d cluster delete three-tier
```
