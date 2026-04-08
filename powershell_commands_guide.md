# 🖥️ PowerShell Commands Guide: Every Command for Windows

> **This guide is 100% PowerShell.** Open PowerShell (not Git Bash) and follow every command in order.
> All `kubectl` and `k3d` commands work the same in PowerShell. Only file/system commands are different.

---

# PHASE 0: Open PowerShell

1. Press `Win + R` → type `powershell` → press Enter
2. Navigate to your project:

```powershell
cd E:\Abluva\k3d-3tier
```

Verify you're in the right place:

```powershell
Get-Location
```

**Expected:**
```
Path
----
E:\Abluva\k3d-3tier
```

---

# PHASE 1: Check Prerequisites

> 🍔 "Before building the restaurant, check if you have all the tools."

---

### Command 1: Check Docker

```powershell
docker --version
```

**Expected:**
```
Docker version 27.5.1, build 9f9e405
```

> ❌ If error → Install Docker Desktop from https://docs.docker.com/desktop/install/windows-install/

---

### Command 2: Is Docker running?

```powershell
docker info 2>$null | Select-Object -First 1
if ($?) { Write-Host "Docker is RUNNING ✅" -ForegroundColor Green } else { Write-Host "Docker is NOT running ❌" -ForegroundColor Red }
```

**Expected:**
```
Client: Docker Engine - Community
Docker is RUNNING ✅
```

> ❌ If NOT running → Open **Docker Desktop** from Start Menu, wait for green whale icon in taskbar.

---

### Command 3: Check k3d

```powershell
k3d version
```

**Expected:**
```
k3d version v5.7.5
k3s version v1.30.6-k3s1 (default)
```

> ❌ If error → Install: `choco install k3d` or `winget install k3d`

---

### Command 4: Check kubectl

```powershell
kubectl version --client
```

**Expected:**
```
Client Version: v1.29.0
```

---

### Command 5: Check Helm

```powershell
helm version --short
```

**Expected:**
```
v3.16.4+gf5e2bda
```

---

### Command 6: See your project files

```powershell
Get-ChildItem -Path . -Recurse -Include *.yaml,*.sh,*.md | Select-Object FullName
```

**Expected:**
```
E:\Abluva\k3d-3tier\namespaces.yaml
E:\Abluva\k3d-3tier\README.md
E:\Abluva\k3d-3tier\cluster-setup.sh
E:\Abluva\k3d-3tier\backend\deployment.yaml
E:\Abluva\k3d-3tier\backend\service.yaml
E:\Abluva\k3d-3tier\db\pod.yaml
E:\Abluva\k3d-3tier\frontend\deployment.yaml
E:\Abluva\k3d-3tier\frontend\service.yaml
E:\Abluva\k3d-3tier\pdb\backend-pdb.yaml
E:\Abluva\k3d-3tier\pdb\frontend-pdb.yaml
E:\Abluva\k3d-3tier\policies\kyverno-policies.yaml
E:\Abluva\k3d-3tier\policies\network-policy.yaml
E:\Abluva\k3d-3tier\security\trivy-scan.sh
E:\Abluva\k3d-3tier\tests\validate.sh
```

---

### Command 7: Read a file (PowerShell way)

```powershell
Get-Content namespaces.yaml
```

**This replaces Linux's `cat` command.** Use `Get-Content <filename>` anytime you want to see a file.

---

# PHASE 2: Create the Cluster

> 🍔 "Build the restaurant — 1 manager office + 3 work floors."

---

### Command 8: Delete any old cluster

```powershell
k3d cluster delete three-tier 2>$null
Write-Host "Clean slate ready" -ForegroundColor Green
```

**Expected:**
```
Clean slate ready
```

---

### Command 9: Create the cluster 🚀

```powershell
k3d cluster create three-tier `
  --servers 1 `
  --agents 3 `
  --api-port 127.0.0.1:6550 `
  --k3s-arg "--disable=traefik@server:*" `
  --wait
```

> ⚠️ **PowerShell Note:** In PowerShell, the line continuation character is **backtick** ( \` ) NOT backslash ( \\ ). That's the key below Esc on your keyboard.

> ⚠️ **Important:** We use `127.0.0.1:6550` to avoid the `host.docker.internal` connection error on Windows.

**⏱️ Wait 30-60 seconds.**

**Expected:**
```
INFO[0000] Prep: Network
INFO[0000] Created network 'k3d-three-tier'
...
INFO[0040] Cluster 'three-tier' created successfully!
```

---

### Command 10: Verify nodes are running

```powershell
kubectl get nodes
```

**Expected:**
```
NAME                        STATUS   ROLES                  AGE   VERSION
k3d-three-tier-agent-0      Ready    <none>                 30s   v1.31.5+k3s1
k3d-three-tier-agent-1      Ready    <none>                 30s   v1.31.5+k3s1
k3d-three-tier-agent-2      Ready    <none>                 30s   v1.31.5+k3s1
k3d-three-tier-server-0     Ready    control-plane,master   50s   v1.31.5+k3s1
```

**✅ 4 nodes, all `Ready`.** If any says `NotReady`, wait 30 seconds and retry.

---

### Command 11: See Docker containers behind the scenes

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}" | Select-String "three-tier"
```

**Expected:** 5 containers (server, 3 agents, loadbalancer) all showing `Up`.

---

# PHASE 3: Label the Nodes

> 🍔 "Put department signs on each floor."

---

### Command 12: Label agent-0 as frontend

```powershell
kubectl label node k3d-three-tier-agent-0 tier=frontend --overwrite
```

**Expected:** `node/k3d-three-tier-agent-0 labeled`

---

### Command 13: Label agent-1 as backend

```powershell
kubectl label node k3d-three-tier-agent-1 tier=backend --overwrite
```

**Expected:** `node/k3d-three-tier-agent-1 labeled`

---

### Command 14: Label agent-2 as db

```powershell
kubectl label node k3d-three-tier-agent-2 tier=db --overwrite
```

**Expected:** `node/k3d-three-tier-agent-2 labeled`

---

### Command 15: Verify labels ⭐

```powershell
kubectl get nodes -L tier
```

**Expected:**
```
NAME                        STATUS   ROLES                  AGE   VERSION        TIER
k3d-three-tier-agent-0      Ready    <none>                 2m    v1.31.5+k3s1   frontend
k3d-three-tier-agent-1      Ready    <none>                 2m    v1.31.5+k3s1   backend
k3d-three-tier-agent-2      Ready    <none>                 2m    v1.31.5+k3s1   db
k3d-three-tier-server-0     Ready    control-plane,master   2m    v1.31.5+k3s1
```

**Check the TIER column!**

---

# PHASE 4: Create the Namespace

> 🍔 "Put the 'QuickBite' company nameplate on the door."

---

### Command 16: Read the namespace file

```powershell
Get-Content namespaces.yaml
```

---

### Command 17: Create namespace

```powershell
kubectl apply -f namespaces.yaml
```

**Expected:** `namespace/three-tier created`

---

### Command 18: Verify

```powershell
kubectl get namespaces | Select-String "three-tier"
```

**Expected:** `three-tier   Active   5s`

---

# PHASE 5: Deploy Frontend

> 🍔 "Hire 2 receptionists for Floor 1."

---

### Command 19: Read the frontend deployment

```powershell
Get-Content frontend\deployment.yaml
```

> Notice: `replicas: 2`, `nodeSelector: tier: frontend`, `image: nginx:1.25.4`

---

### Command 20: Deploy frontend

```powershell
kubectl apply -f frontend\deployment.yaml
```

**Expected:** `deployment.apps/frontend created`

---

### Command 21: Deploy frontend service

```powershell
kubectl apply -f frontend\service.yaml
```

**Expected:** `service/frontend-svc created`

---

### Command 22: Watch pods starting (press Ctrl+C to stop)

```powershell
kubectl get pods -n three-tier -w
```

**Wait until both frontend pods show `Running`, then press `Ctrl+C`.**

---

# PHASE 6: Deploy Backend

> 🍔 "Hire 2 chefs for Floor 2."

---

### Command 23: Deploy backend

```powershell
kubectl apply -f backend\deployment.yaml
```

**Expected:** `deployment.apps/backend created`

---

### Command 24: Deploy backend service

```powershell
kubectl apply -f backend\service.yaml
```

**Expected:** `service/backend-svc created`

---

# PHASE 7: Deploy Database

> 🍔 "Hire 1 storage clerk for Floor 3."

---

### Command 25: Deploy database

```powershell
kubectl apply -f db\pod.yaml
```

**Expected:**
```
pod/db created
service/db-svc created
```

---

### Command 26: Verify ALL pods ⭐⭐⭐

```powershell
kubectl get pods -n three-tier -o wide
```

**Expected:**
```
NAME                        READY   STATUS    NODE
frontend-xxxxx-yyyyy        1/1     Running   k3d-three-tier-agent-0
frontend-xxxxx-zzzzz        1/1     Running   k3d-three-tier-agent-0
backend-xxxxx-yyyyy         1/1     Running   k3d-three-tier-agent-1
backend-xxxxx-zzzzz         1/1     Running   k3d-three-tier-agent-1
db                          1/1     Running   k3d-three-tier-agent-2
```

**✅ Check:** 5 pods, all `Running`, each on the correct node.

---

### Command 27: Check services

```powershell
kubectl get services -n three-tier
```

**Expected:** 3 services — `frontend-svc:80`, `backend-svc:8080`, `db-svc:3306`

---

# PHASE 8: Apply PDBs

> 🍔 "Set the 'minimum 1 staff on duty' rule."

---

### Command 28: Read the PDB file

```powershell
Get-Content pdb\frontend-pdb.yaml
```

---

### Command 29: Apply both PDBs

```powershell
kubectl apply -f pdb\frontend-pdb.yaml
kubectl apply -f pdb\backend-pdb.yaml
```

**Expected:**
```
poddisruptionbudget.policy/frontend-pdb created
poddisruptionbudget.policy/backend-pdb created
```

---

### Command 30: Verify PDBs

```powershell
kubectl get pdb -n three-tier
```

**Expected:**
```
NAME           MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
frontend-pdb   1               N/A               1                     5s
backend-pdb    1               N/A               1                     5s
```

---

# PHASE 9: Apply Network Policies

> 🍔 "Lock all doors, then give specific keys."

---

### Command 31: Read network policies

```powershell
Get-Content policies\network-policy.yaml
```

---

### Command 32: Apply network policies

```powershell
kubectl apply -f policies\network-policy.yaml
```

**Expected:** 6 networkpolicies created.

---

### Command 33: Verify all 6 policies

```powershell
kubectl get networkpolicy -n three-tier
```

**Expected:** 6 policies listed.

---

# PHASE 10: Install Kyverno

> 🍔 "Hire the security guard."

---

### Command 34: Add Kyverno repo to Helm

```powershell
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>$null
helm repo update
```

---

### Command 35: Install Kyverno (~1-2 minutes)

```powershell
helm install kyverno kyverno/kyverno `
  --namespace kyverno `
  --create-namespace `
  --wait
```

**⏱️ Wait 1-2 minutes.**

**Expected:**
```
NAME: kyverno
STATUS: deployed
```

---

### Command 36: Verify Kyverno is running

```powershell
kubectl get pods -n kyverno
```

**Expected:** 4 pods, all `Running`.

---

### Command 37: Read Kyverno policies

```powershell
Get-Content policies\kyverno-policies.yaml
```

---

### Command 38: Apply Kyverno policies

```powershell
kubectl apply -f policies\kyverno-policies.yaml
```

**Expected:**
```
clusterpolicy.kyverno.io/disallow-privileged-containers created
clusterpolicy.kyverno.io/disallow-latest-tag created
```

---

### Command 39: Verify policies are active

```powershell
kubectl get clusterpolicy
```

**Expected:** Both show `READY = True` and `VALIDATE ACTION = Enforce`.

---

# PHASE 11: Verify Everything

> 🍔 "Final check — is the restaurant fully open?"

---

### Command 40: Show all pods with node info

```powershell
kubectl get pods -n three-tier -o wide
```

---

### Command 41: Show everything at once

```powershell
kubectl get all -n three-tier
```

---

# PHASE 12: Test Network Policies

> 🍔 "Try opening doors and see which are locked!"

---

### Command 42: Frontend → Backend (Should ✅ WORK)

```powershell
kubectl exec -n three-tier deploy/frontend -- sh -c "apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq curl > /dev/null 2>&1 && curl -s --max-time 5 http://backend-svc:8080"
```

> ⚠️ The `sh -c "..."` part runs INSIDE the Linux container, so it stays in Linux syntax. That's normal!

**Expected:** HTML output (directory listing). ✅ Connection works!

---

### Command 43: Frontend → Database (Should ❌ FAIL)

```powershell
kubectl exec -n three-tier deploy/frontend -- sh -c "curl -s --max-time 5 http://db-svc:3306 || echo 'BLOCKED by NetworkPolicy'"
```

**Expected:** `BLOCKED by NetworkPolicy` or timeout. ❌ Correctly blocked!

---

### Command 44: Backend → Database (Should ✅ WORK)

```powershell
kubectl exec -n three-tier deploy/backend -- python -c "import socket; s=socket.socket(); s.settimeout(5); s.connect(('db-svc', 3306)); print('DB OK'); s.close()"
```

**Expected:** `DB OK` ✅

---

### Command 45: Database → Frontend (Should ❌ FAIL)

```powershell
kubectl exec -n three-tier db -- sh -c "wget -qO- --timeout=3 http://frontend-svc:80 || echo 'BLOCKED'"
```

**Expected:** `BLOCKED` ❌

---

# PHASE 13: Test Kyverno Security

> 🍔 "Try sneaking past the security guard!"

---

### Command 46: Try privileged container (Should ❌ FAIL)

```powershell
kubectl run test-privileged --image=nginx:1.25.4 -n three-tier --overrides='{\"spec\":{\"containers\":[{\"name\":\"test-privileged\",\"image\":\"nginx:1.25.4\",\"securityContext\":{\"privileged\":true}}]}}'
```

> ⚠️ **PowerShell Note:** JSON inside PowerShell needs escaped quotes `\"` instead of regular `"`.

**Expected error:** `admission webhook denied the request: Privileged containers are not allowed`

✅ **BLOCKED! Security guard working!**

---

### Command 47: Try :latest tag (Should ❌ FAIL)

```powershell
kubectl run test-latest --image=nginx:latest -n three-tier
```

**Expected error:** `admission webhook denied the request: Using ':latest' tag is not allowed`

✅ **BLOCKED!**

---

### Command 48: Try no tag (Should ❌ FAIL)

```powershell
kubectl run test-notag --image=nginx -n three-tier
```

**Expected error:** `An image tag is required`

✅ **BLOCKED! All 3 security tests pass!**

---

### Command 49: Clean up any test pods

```powershell
kubectl delete pod test-privileged test-latest test-notag -n three-tier --ignore-not-found 2>$null
```

---

# PHASE 14: Test PDB (Node Drain)

> 🍔 "Renovate a floor and prove the restaurant stays open!"

---

### Command 50: Check PDB status

```powershell
kubectl get pdb -n three-tier
```

---

### Command 51: Get the frontend node name

```powershell
$FRONTEND_NODE = kubectl get nodes -l tier=frontend -o jsonpath='{.items[0].metadata.name}'
Write-Host "Frontend node is: $FRONTEND_NODE"
```

**Expected:** `Frontend node is: k3d-three-tier-agent-0`

---

### Command 52: Drain the node (start renovation!)

```powershell
kubectl drain $FRONTEND_NODE --ignore-daemonsets --delete-emptydir-data
```

**Expected:**
```
node/k3d-three-tier-agent-0 cordoned
evicting pod three-tier/frontend-xxxxx
...
node/k3d-three-tier-agent-0 drained
```

---

### Command 53: Check pods after drain

```powershell
kubectl get pods -n three-tier -o wide
```

**Expected:** Frontend pods in `Pending` (their node is closed), backend and db still `Running`.

---

### Command 54: Uncordon (finish renovation!)

```powershell
kubectl uncordon $FRONTEND_NODE
```

**Expected:** `node/k3d-three-tier-agent-0 uncordoned`

---

### Command 55: Wait and verify recovery

```powershell
Start-Sleep -Seconds 15
kubectl get pods -n three-tier -o wide
```

**Expected:** All 5 pods back to `Running`. ✅

---

# PHASE 15: Check Resources

> 🍔 "Verify every employee has defined desk size and cabinet limits."

---

### Command 56: Show resources for all pods

```powershell
kubectl get pods -n three-tier -o jsonpath='{range .items[*]}{"Pod: "}{.metadata.name}{"\n  Requests: "}{.spec.containers[0].resources.requests}{"\n  Limits:   "}{.spec.containers[0].resources.limits}{"\n\n"}{end}'
```

**Expected:** Every pod shows cpu and memory for both requests and limits.

---

# PHASE 16: Run Automated Tests

> The `validate.sh` is a bash script, so you need Git Bash for this ONE step:

### Command 57: Run tests (in Git Bash)

```powershell
# Option A: Run via Git Bash from PowerShell
& "C:\Program Files\Git\bin\bash.exe" -c "./tests/validate.sh"
```

```powershell
# Option B: If that doesn't work, just open Git Bash manually:
# Right-click project folder → Git Bash Here → type:
# chmod +x tests/validate.sh && ./tests/validate.sh
```

---

# PHASE 17: Cleanup

> 🍔 "Close the restaurant and demolish the building."

---

### Command 58: Delete the cluster

```powershell
k3d cluster delete three-tier
```

**Expected:**
```
INFO[0000] Deleting cluster 'three-tier'
...
INFO[0010] Successfully deleted cluster three-tier!
```

---

### Command 59: Verify it's gone

```powershell
k3d cluster list
```

**Expected:** Empty list.

---

# 📋 PowerShell vs Linux Cheat Sheet

| Action | Linux/Bash | PowerShell |
|---|---|---|
| Read a file | `cat file.yaml` | `Get-Content file.yaml` |
| List files | `ls -la` | `Get-ChildItem` or `dir` |
| Find files | `find . -name "*.yaml"` | `Get-ChildItem -Recurse -Include *.yaml` |
| Search text in file | `grep "word" file` | `Select-String "word" file` |
| Search in output | `cmd \| grep "word"` | `cmd \| Select-String "word"` |
| Wait/sleep | `sleep 15` | `Start-Sleep -Seconds 15` |
| Store in variable | `VAR=$(command)` | `$VAR = command` |
| Suppress errors | `2>/dev/null` | `2>$null` |
| And (run both) | `cmd1 && cmd2` | `cmd1; if ($?) { cmd2 }` |
| Line continuation | `\` (backslash) | `` ` `` (backtick) |
| File path separator | `/` (forward slash) | `\` (backslash) |
| Run bash script | `./script.sh` | `& "C:\Program Files\Git\bin\bash.exe" -c "./script.sh"` |
| Print text | `echo "text"` | `Write-Host "text"` |
| Clear screen | `clear` | `cls` or `Clear-Host` |

> ⚠️ **Important:** All `kubectl exec ... -- sh -c "..."` commands use **Linux syntax inside the quotes** because the command runs INSIDE the Linux container, not on your Windows machine. Don't change those!

---

# 🚀 ONE-SHOT: Do Everything in 5 Commands

If you just want to get everything running fast:

```powershell
# 1. Create cluster
k3d cluster create three-tier --servers 1 --agents 3 --api-port 127.0.0.1:6550 --k3s-arg "--disable=traefik@server:*" --wait

# 2. Label nodes
kubectl label node k3d-three-tier-agent-0 tier=frontend --overwrite; kubectl label node k3d-three-tier-agent-1 tier=backend --overwrite; kubectl label node k3d-three-tier-agent-2 tier=db --overwrite

# 3. Deploy everything
kubectl apply -f namespaces.yaml; kubectl apply -f frontend\deployment.yaml; kubectl apply -f frontend\service.yaml; kubectl apply -f backend\deployment.yaml; kubectl apply -f backend\service.yaml; kubectl apply -f db\pod.yaml; kubectl apply -f pdb\frontend-pdb.yaml; kubectl apply -f pdb\backend-pdb.yaml; kubectl apply -f policies\network-policy.yaml

# 4. Install Kyverno + policies
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>$null; helm repo update; helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace --wait; kubectl apply -f policies\kyverno-policies.yaml

# 5. Verify
kubectl get pods -n three-tier -o wide
```

---

**🎉 You now have a complete PowerShell guide!**
