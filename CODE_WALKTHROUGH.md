# 🔍 Line-by-line Code Walkthrough

This document explains the "How it works" at the code level. Perfect for answering: *"How did you implement X?"* in an interview.

---

## 🛡️ 1. The Zero-Trust Network (network-policy.yaml)

### **The Default Deny**
```yaml
spec:
  podSelector: {}
  policyTypes: [- Ingress, - Egress]
```
- **Why:** By leaving `podSelector` empty (`{}`), it matches **every** pod in the namespace. Since no `ingress` or `egress` rules are defined below it, Kubernetes blocks all traffic. This is the foundation of Zero-Trust.

### **The DNS Lifeline**
```yaml
egress:
  - to: [{ namespaceSelector: {} }]
    ports: [{ protocol: UDP, port: 53 }]
```
- **Why:** Even with a deny-all policy, pods need to talk to the Kubernetes DNS service (CoreDNS) to resolve service names (like `backend-svc`). Without this rule, your app would break because it couldn't find its own components.

---

## ⚖️ 2. Advanced Scheduling (frontend/deployment.yaml)

### **Node Affinity (The 70/30 Split)**
```yaml
nodeAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 70
      preference: { matchExpressions: [{ key: pool, operator: In, values: [spot] }] }
```
- **Explain:** We use `preferred` (Soft Affinity) so that if Spot nodes are unavailable, pods can still run on Reserved. The `weight: 70` tells the scheduler's scoring algorithm to give a massive "bonus" to Spot nodes.

### **Topology Spread Constraints**
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: pool
    whenUnsatisfiable: ScheduleAnyway
```
- **Explain:** This prevents "clumping." `maxSkew: 1` means the difference in pod counts between pools cannot be more than 1. It forces the scheduler to distribute pods evenly across the pools.

---

## 🚫 3. Security Enforcement (kyverno-policies.yaml)

### **Disallow Privileged Containers**
```yaml
validate:
  message: "Privileged containers are not allowed."
  pattern:
    spec:
      containers:
        - =(securityContext):
            =(privileged): false
```
- **Explain:** This uses a `validate.pattern`. The Admission Controller compares the incoming Pod request to this pattern. If `privileged: true` is found, the request is rejected with the message.

---

## 🐚 4. The Logic in `cluster-setup.sh`

### **Cross-Platform Compatibility**
```bash
if command -v k3d &>/dev/null; then 
  K3D_CMD="k3d"
elif command -v k3d.exe &>/dev/null; then
  K3D_CMD="k3d.exe"
fi
```
- **Explain:** This makes the script work on both native Linux and Windows (WSL/Git Bash). It detects if the `.exe` version of the tool is in the path.

### **The Idempotent Setup**
```bash
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  k3d cluster delete "$CLUSTER_NAME"
fi
```
- **Explain:** The script is "idempotent" and "self-cleaning." It checks if a cluster exists and deletes it first, ensuring you always start from a known good state.

### **The Readiness Loop**
```bash
while [ $elapsed -lt $timeout ]; do
  # ... check kubectl get pods ...
done
```
- **Explain:** Instead of using fixed `sleep` commands (which are unreliable), I implemented a polling loop that checks the status of every container in the namespace. The script only finishes when the "Ready" count equals the "Total" count.
