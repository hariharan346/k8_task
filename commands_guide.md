# 🖥️ Hands-On Command Guide: Every Single Command, Step by Step

> **How to use this guide:** Open **Git Bash** on Windows, and follow every command in order. Don't skip any. I'll explain what each command does before you run it.

---

# PHASE 0: Open Your Terminal

**On Windows:**
1. Open **File Explorer** → Go to `E:\Abluva\k3d-3tier`
2. Right-click on empty space → Select **"Open Git Bash here"**
3. You should see something like:

```
user@DESKTOP MINGW64 /e/Abluva/k3d-3tier
$
```

You're now inside your project folder. Let's begin!

---

# PHASE 1: Check Prerequisites (Do I Have All the Tools?)

> 🍔 **QuickBite Analogy:** Before building a restaurant, check if you have a hammer, nails, paint, and brushes. If anything is missing, you can't build!

---

### Command 1: Check if Docker is installed

```bash
docker --version
```

**What this does:** Asks "Hey, is Docker installed on my computer?"

**Expected output:**
```
Docker version 27.5.1, build 9f9e405
```

> If you see `command not found` → Docker is NOT installed. Go install it from https://docs.docker.com/desktop/install/windows-install/ and restart your computer.

---

### Command 2: Check if Docker is actually running

```bash
docker info > /dev/null 2>&1 && echo "Docker is RUNNING ✅" || echo "Docker is NOT running ❌"
```

**What this does:** Checks if Docker Desktop is open and the engine is running (not just installed).

**Expected output:**
```
Docker is RUNNING ✅
```

> If you see ❌ → Open **Docker Desktop** from your Start menu. Wait until the whale icon in the taskbar turns steady (not animated). Then try again.

---

### Command 3: Check if k3d is installed

```bash
k3d version
```

**What this does:** "Is the mini-Kubernetes builder (k3d) installed?"

**Expected output:**
```
k3d version v5.7.5
k3s version v1.30.6-k3s1 (default)
```

> If `command not found` → Install it:
> ```bash
> curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
> ```

---

### Command 4: Check if kubectl is installed

```bash
kubectl version --client
```

**What this does:** "Is the Kubernetes steering wheel (kubectl) installed?"

**Expected output:**
```
Client Version: v1.29.0
```

---

### Command 5: Check if Helm is installed

```bash
helm version --short
```

**What this does:** "Is the app store installer (Helm) installed?"

**Expected output:**
```
v3.16.4+gf5e2bda
```

---

### Command 6: Look at your project files

```bash
ls -la
```

**What this does:** Lists everything in your project folder.

**Expected output:**
```
drwxr-xr-x  backend/
drwxr-xr-x  db/
drwxr-xr-x  frontend/
drwxr-xr-x  pdb/
drwxr-xr-x  policies/
drwxr-xr-x  security/
drwxr-xr-x  tests/
-rwxr-xr-x  cluster-setup.sh
-rw-r--r--  namespaces.yaml
-rw-r--r--  README.md
```

> 🍔 **Analogy:** You're looking at the blueprint files for your restaurant. Each folder is a department's plan.

---

### Command 7: See what's inside each folder

```bash
find . -name "*.yaml" -o -name "*.sh" | sort
```

**What this does:** Lists every YAML and shell script file in the project.

**Expected output:**
```
./backend/deployment.yaml
./backend/service.yaml
./cluster-setup.sh
./db/pod.yaml
./frontend/deployment.yaml
./frontend/service.yaml
./namespaces.yaml
./pdb/backend-pdb.yaml
./pdb/frontend-pdb.yaml
./policies/kyverno-policies.yaml
./policies/network-policy.yaml
./security/trivy-scan.sh
./tests/validate.sh
```

**You have 11 files. Each one does something specific. Let's use them one by one.**

---

# PHASE 2: Create the Kubernetes Cluster

> 🍔 **QuickBite Analogy:** "Build the restaurant building — 1 manager's office + 3 work floors."

---

### Command 8: Delete any old cluster (cleanup first)

```bash
k3d cluster delete three-tier 2>/dev/null; echo "Clean slate ready"
```

**What this does:** If you ran this project before, this removes the old cluster. If not, it does nothing.

**Expected output:**
```
Clean slate ready
```

---

### Command 9: Create the cluster 🚀

```bash
k3d cluster create three-tier \
  --servers 1 \
  --agents 3 \
  --k3s-arg "--disable=traefik@server:*" \
  --wait
```

**What this does line by line:**
- `k3d cluster create three-tier` → "Build a building called 'three-tier'"
- `--servers 1` → "1 manager's office (control plane)"
- `--agents 3` → "3 work floors (worker nodes)"
- `--k3s-arg "--disable=traefik@server:*"` → "Don't install the default web router"
- `--wait` → "Don't come back until building is fully constructed"

**⏱️ This takes 30-60 seconds. Wait for it.**

**Expected output:**
```
INFO[0000] Prep: Network
INFO[0000] Created network 'k3d-three-tier'
INFO[0000] Created image volume k3d-three-tier-images
INFO[0000] Starting new tools node...
INFO[0001] Creating node 'k3d-three-tier-server-0'
INFO[0001] Creating node 'k3d-three-tier-agent-0'
INFO[0001] Creating node 'k3d-three-tier-agent-1'
INFO[0001] Creating node 'k3d-three-tier-agent-2'
...
INFO[0025] Cluster 'three-tier' created successfully!
```

> 🍔 **What just happened:** k3d created 4 Docker containers — each one pretends to be a server. Together they form a Kubernetes cluster.

---

### Command 10: Verify the cluster is running

```bash
kubectl get nodes
```

**What this does:** "Show me all the machines (nodes) in my cluster."

**Expected output:**
```
NAME                        STATUS   ROLES                  AGE   VERSION
k3d-three-tier-agent-0      Ready    <none>                 30s   v1.30.6+k3s1
k3d-three-tier-agent-1      Ready    <none>                 30s   v1.30.6+k3s1
k3d-three-tier-agent-2      Ready    <none>                 30s   v1.30.6+k3s1
k3d-three-tier-server-0     Ready    control-plane,master   35s   v1.30.6+k3s1
```

**You should see 4 nodes, all `Ready`.** If any says `NotReady`, wait 30 seconds and try again.

> 🍔 **Analogy:** "Your building is built! 1 manager's office (server-0) and 3 empty floors (agent-0, 1, 2). All are operational."

---

### Command 11: See the Docker containers behind the scenes

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep three-tier
```

**What this does:** Shows the actual Docker containers running your cluster.

**Expected output:**
```
k3d-three-tier-agent-2      Up 1 minute
k3d-three-tier-agent-1      Up 1 minute
k3d-three-tier-agent-0      Up 1 minute
k3d-three-tier-server-0     Up 1 minute
k3d-three-tier-serverlb     Up 1 minute
```

> 🍔 **Behind the scenes:** Each "node" is actually a Docker container. k3d is clever — it fakes a multi-server setup on your single laptop!

---

# PHASE 3: Label the Nodes (Put Department Signs)

> 🍔 **Analogy:** "Put signs on each floor — Floor 1: Customer Service, Floor 2: Kitchen, Floor 3: Storage."

---

### Command 12: Label agent-0 as frontend

```bash
kubectl label node k3d-three-tier-agent-0 tier=frontend --overwrite
```

**What this does:** Sticks a label `tier=frontend` on agent-0.

**Expected output:**
```
node/k3d-three-tier-agent-0 labeled
```

---

### Command 13: Label agent-1 as backend

```bash
kubectl label node k3d-three-tier-agent-1 tier=backend --overwrite
```

**Expected output:**
```
node/k3d-three-tier-agent-1 labeled
```

---

### Command 14: Label agent-2 as db

```bash
kubectl label node k3d-three-tier-agent-2 tier=db --overwrite
```

**Expected output:**
```
node/k3d-three-tier-agent-2 labeled
```

---

### Command 15: Verify all labels are correct ⭐

```bash
kubectl get nodes -L tier
```

**What this does:** Shows all nodes WITH a column for the `tier` label.

**Expected output:**
```
NAME                        STATUS   ROLES                  AGE   VERSION        TIER
k3d-three-tier-agent-0      Ready    <none>                 2m    v1.30.6+k3s1   frontend
k3d-three-tier-agent-1      Ready    <none>                 2m    v1.30.6+k3s1   backend
k3d-three-tier-agent-2      Ready    <none>                 2m    v1.30.6+k3s1   db
k3d-three-tier-server-0     Ready    control-plane,master   2m    v1.30.6+k3s1
```

**Check the TIER column:** agent-0=frontend, agent-1=backend, agent-2=db. Server-0 has NO tier (it's the manager, it doesn't run apps).

> 🍔 **Analogy:** "Signs are up! Now when we hire employees, they'll know which floor to go to."

---

# PHASE 4: Create the Namespace (Name Your Company)

> 🍔 **Analogy:** "Put the 'QuickBite' nameplate on the building door."

---

### Command 16: Look at what we're about to create

```bash
cat namespaces.yaml
```

**What this does:** Shows the file contents. You'll see:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: three-tier
  labels:
    name: three-tier
```

> This creates a namespace called `three-tier` — a separate space for our app so it doesn't mix with system stuff.

---

### Command 17: Create the namespace

```bash
kubectl apply -f namespaces.yaml
```

**What this does:** "Kubernetes, please create whatever is described in this file."

**Expected output:**
```
namespace/three-tier created
```

---

### Command 18: Verify namespace exists

```bash
kubectl get namespaces | grep three-tier
```

**Expected output:**
```
three-tier        Active   5s
```

> 🍔 **From now on, all our commands will use `-n three-tier`** to tell Kubernetes "I'm talking about stuff in the three-tier namespace."

---

# PHASE 5: Deploy the Frontend (Hire Receptionists)

> 🍔 **Analogy:** "Hire 2 receptionists and assign them to Floor 1 (Customer Service)."

---

### Command 19: Look at the frontend deployment file

```bash
cat frontend/deployment.yaml
```

**Read through it. Key things to notice:**
- `replicas: 2` → 2 employees
- `nodeSelector: tier: frontend` → Only on the frontend floor
- `image: nginx:1.25.4` → Using nginx web server version 1.25.4
- `resources:` → Each employee needs 100m CPU and 64Mi memory minimum

---

### Command 20: Deploy the frontend

```bash
kubectl apply -f frontend/deployment.yaml
```

**Expected output:**
```
deployment.apps/frontend created
```

> 🍔 **What happened:** Kubernetes read the file and said "OK, I'll create 2 nginx pods and put them on the node labeled tier=frontend."

---

### Command 21: Deploy the frontend service (give it a phone number)

```bash
kubectl apply -f frontend/service.yaml
```

**Expected output:**
```
service/frontend-svc created
```

> 🍔 **Now other pods can call `frontend-svc:80` to reach the frontend, no matter which pod is actually running.**

---

### Command 22: Check if frontend pods are starting

```bash
kubectl get pods -n three-tier -w
```

**What this does:** Watches pods in real-time. You'll see them go through stages:

```
NAME                        READY   STATUS              AGE
frontend-7d4b8c6f9-abc12    0/1     ContainerCreating   3s
frontend-7d4b8c6f9-def34    0/1     ContainerCreating   3s
frontend-7d4b8c6f9-abc12    1/1     Running             15s
frontend-7d4b8c6f9-def34    1/1     Running             18s
```

**Press `Ctrl+C` to stop watching** once both show `Running`.

> 🍔 **The stages:**
> - `ContainerCreating` = "Employee is setting up their desk"
> - `Running` = "Employee is at their desk, ready to work! ✅"

---

# PHASE 6: Deploy the Backend (Hire Chefs)

> 🍔 **Analogy:** "Hire 2 chefs and assign them to Floor 2 (Kitchen)."

---

### Command 23: Deploy the backend

```bash
kubectl apply -f backend/deployment.yaml
```

**Expected output:**
```
deployment.apps/backend created
```

---

### Command 24: Deploy the backend service

```bash
kubectl apply -f backend/service.yaml
```

**Expected output:**
```
service/backend-svc created
```

---

# PHASE 7: Deploy the Database (Hire Storage Clerk)

> 🍔 **Analogy:** "Hire 1 storage clerk for Floor 3."

---

### Command 25: Deploy the database pod + service

```bash
kubectl apply -f db/pod.yaml
```

**Expected output:**
```
pod/db created
service/db-svc created
```

> This file contains BOTH the Pod AND the Service (separated by `---` in YAML). So one command creates both!

---

### Command 26: Check ALL pods are running ⭐⭐⭐

```bash
kubectl get pods -n three-tier -o wide
```

**This is the MOST IMPORTANT command. Expected output:**

```
NAME                        READY   STATUS    RESTARTS   AGE   IP           NODE
frontend-7d4b8c6f9-abc12    1/1     Running   0          2m    10.42.0.5    k3d-three-tier-agent-0
frontend-7d4b8c6f9-def34    1/1     Running   0          2m    10.42.0.6    k3d-three-tier-agent-0
backend-5c8d9e7f1-ghi56     1/1     Running   0          1m    10.42.1.3    k3d-three-tier-agent-1
backend-5c8d9e7f1-jkl78     1/1     Running   0          1m    10.42.1.4    k3d-three-tier-agent-1
db                          1/1     Running   0          30s   10.42.2.2    k3d-three-tier-agent-2
```

**✅ CHECK THESE 3 THINGS:**

| What to check | Expected | Column |
|---|---|---|
| All 5 pods exist | 2 frontend + 2 backend + 1 db | NAME |
| All show `Running` | Not Pending, not CrashLoop | STATUS |
| Each is on the right node | frontend→agent-0, backend→agent-1, db→agent-2 | NODE |

> 🍔 **Analogy:** "All employees are at their desks, on the right floors! The restaurant is open!"

If a pod is stuck in `Pending`, run:
```bash
kubectl describe pod <pod-name> -n three-tier
```
Scroll to the **Events** section at the bottom to see why.

---

### Command 27: Check services are created

```bash
kubectl get services -n three-tier
```

**Expected output:**
```
NAME           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
frontend-svc   ClusterIP   10.43.100.50    <none>        80/TCP     3m
backend-svc    ClusterIP   10.43.100.51    <none>        8080/TCP   2m
db-svc         ClusterIP   10.43.100.52    <none>        3306/TCP   1m
```

> 🍔 **Three permanent phone numbers are set up:** `frontend-svc:80`, `backend-svc:8080`, `db-svc:3306`

---

# PHASE 8: Apply PodDisruptionBudgets (Set Minimum Staff Rules)

> 🍔 **Analogy:** "Rule: Even during renovation, keep at least 1 receptionist and 1 chef on duty."

---

### Command 28: Look at the frontend PDB

```bash
cat pdb/frontend-pdb.yaml
```

**You'll see `minAvailable: 1` — "at least 1 frontend pod must stay running at all times."**

---

### Command 29: Apply both PDBs

```bash
kubectl apply -f pdb/frontend-pdb.yaml
kubectl apply -f pdb/backend-pdb.yaml
```

**Expected output:**
```
poddisruptionbudget.policy/frontend-pdb created
poddisruptionbudget.policy/backend-pdb created
```

---

### Command 30: Verify PDBs are active

```bash
kubectl get pdb -n three-tier
```

**Expected output:**
```
NAME           MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
frontend-pdb   1               N/A               1                     5s
backend-pdb    1               N/A               1                     5s
```

**Key column: `ALLOWED DISRUPTIONS = 1`** → means Kubernetes can evict 1 pod at a time (since we have 2 replicas and need minimum 1).

---

# PHASE 9: Apply Network Policies (Install Door Locks)

> 🍔 **Analogy:** "Lock all doors first, then give keys only to those who need them."

---

### Command 31: Look at the network policies

```bash
cat policies/network-policy.yaml
```

**This file has 6 policies. Count the `---` separators — each section is a separate policy.**

---

### Command 32: Apply all network policies

```bash
kubectl apply -f policies/network-policy.yaml
```

**Expected output:**
```
networkpolicy.networking.k8s.io/default-deny-all created
networkpolicy.networking.k8s.io/allow-dns created
networkpolicy.networking.k8s.io/frontend-egress-to-backend created
networkpolicy.networking.k8s.io/backend-ingress-from-frontend created
networkpolicy.networking.k8s.io/backend-egress-to-db created
networkpolicy.networking.k8s.io/db-ingress-from-backend created
```

---

### Command 33: Verify all 6 policies exist

```bash
kubectl get networkpolicy -n three-tier
```

**Expected output:**
```
NAME                            POD-SELECTOR    AGE
default-deny-all                <none>          10s
allow-dns                       <none>          10s
frontend-egress-to-backend      app=frontend    10s
backend-ingress-from-frontend   app=backend     10s
backend-egress-to-db            app=backend     10s
db-ingress-from-backend         app=db          10s
```

> 🍔 **6 policies = 1 (lock all) + 1 (allow DNS) + 2 (frontend↔backend key) + 2 (backend↔db key).**

---

# PHASE 10: Install Kyverno (Hire the Security Guard)

> 🍔 **Analogy:** "Hire a security guard at the building gate who checks everyone's ID before letting them in."

---

### Command 34: Add Kyverno to Helm's app store

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null
helm repo update
```

**What this does:** Tells Helm "I want to install from the Kyverno app store."

**Expected output:**
```
"kyverno" already exists with the same configuration, skipping
...Successfully got an update from the "kyverno" chart repository
Update Complete. ⎈Happy Helming!⎈
```

---

### Command 35: Install Kyverno into the cluster

```bash
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --wait
```

**What this does line by line:**
- `helm install kyverno` → "Install an app called 'kyverno'"
- `kyverno/kyverno` → "From the kyverno store, pick the kyverno package"
- `--namespace kyverno` → "Put it in its own room called 'kyverno'"
- `--create-namespace` → "Create that room if it doesn't exist"
- `--wait` → "Don't finish until it's fully running"

**⏱️ This takes 1-2 minutes.**

**Expected output:**
```
NAME: kyverno
LAST DEPLOYED: Mon Apr  7 09:30:00 2026
NAMESPACE: kyverno
STATUS: deployed
```

---

### Command 36: Verify Kyverno pods are running

```bash
kubectl get pods -n kyverno
```

**Expected output:**
```
NAME                                            READY   STATUS    RESTARTS   AGE
kyverno-admission-controller-xxxxx-yyyyy        1/1     Running   0          60s
kyverno-background-controller-xxxxx-yyyyy       1/1     Running   0          60s
kyverno-cleanup-controller-xxxxx-yyyyy          1/1     Running   0          60s
kyverno-reports-controller-xxxxx-yyyyy          1/1     Running   0          60s
```

> 🍔 **Your security guard is hired and standing at the gate! Now let's give them the rules.**

---

### Command 37: Look at the Kyverno policies

```bash
cat policies/kyverno-policies.yaml
```

**Notice 2 policies:**
1. `disallow-privileged-containers` — "No all-access passes"
2. `disallow-latest-tag` — "No mystery software versions"

---

### Command 38: Apply Kyverno policies

```bash
kubectl apply -f policies/kyverno-policies.yaml
```

**Expected output:**
```
clusterpolicy.kyverno.io/disallow-privileged-containers created
clusterpolicy.kyverno.io/disallow-latest-tag created
```

---

### Command 39: Verify policies are active

```bash
kubectl get clusterpolicy
```

**Expected output:**
```
NAME                              ADMISSION   BACKGROUND   VALIDATE ACTION   READY   AGE
disallow-privileged-containers    true        true         Enforce           True    10s
disallow-latest-tag               true        true         Enforce           True    10s
```

**Key: `READY = True` and `VALIDATE ACTION = Enforce`** — means they will BLOCK (not just warn).

---

# PHASE 11: VERIFY EVERYTHING IS WORKING 🎉

> 🍔 **"The restaurant is built, staffed, secured, and rules are in place. Now let's TEST everything!"**

---

### Command 40: Final status check — all pods

```bash
kubectl get pods -n three-tier -o wide
```

**All 5 pods should be `Running` on their correct nodes.** This is the command interviewers ask for first!

---

### Command 41: Check all resources at once

```bash
kubectl get all -n three-tier
```

**This shows pods, services, and deployments in one view.** Expected:

```
NAME                            READY   STATUS    RESTARTS   AGE
pod/frontend-xxxxx-yyyyy        1/1     Running   0          5m
pod/frontend-xxxxx-zzzzz        1/1     Running   0          5m
pod/backend-xxxxx-yyyyy         1/1     Running   0          4m
pod/backend-xxxxx-zzzzz         1/1     Running   0          4m
pod/db                          1/1     Running   0          3m

NAME                  TYPE        CLUSTER-IP     PORT(S)
service/frontend-svc  ClusterIP   10.43.x.x      80/TCP
service/backend-svc   ClusterIP   10.43.x.x      8080/TCP
service/db-svc        ClusterIP   10.43.x.x      3306/TCP

NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/frontend   2/2     2            2           5m
deployment.apps/backend    2/2     2            2           4m
```

---

# PHASE 12: TEST — Network Policies

> 🍔 **"Let's try opening doors and see which ones are locked!"**

---

### Command 42: Test Frontend → Backend (Should ✅ WORK)

```bash
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq curl > /dev/null 2>&1 && curl -s --max-time 5 http://backend-svc:8080"
```

**What this does:**
1. `kubectl exec ... deploy/frontend --` → "Go inside the frontend pod and run a command"
2. `apt-get install curl` → "Install curl (a tool to make HTTP requests)"
3. `curl http://backend-svc:8080` → "Try to reach the backend"

**Expected output:** An HTML page (directory listing from Python HTTP server):
```
<!DOCTYPE HTML>
<html><head>...
<h1>Directory listing for /</h1>
...
```

**If you see HTML → ✅ Frontend CAN reach Backend! The door key works!**

---

### Command 43: Test Frontend → Database (Should ❌ FAIL)

```bash
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "curl -s --max-time 5 http://db-svc:3306 || echo '❌ BLOCKED - Network Policy working!'"
```

**Expected output:**
```
❌ BLOCKED - Network Policy working!
```

**Or it just hangs for 5 seconds and shows nothing.** Both mean the same thing: the connection was blocked!

> 🍔 **"Receptionist tried to call Storage directly — DOOR LOCKED! No key! This is correct behavior!"**

---

### Command 44: Test Backend → Database (Should ✅ WORK)

```bash
kubectl exec -n three-tier deploy/backend -- \
  python -c "import socket; s=socket.socket(); s.settimeout(5); s.connect(('db-svc', 3306)); print('✅ DB OK - Backend can reach Database!'); s.close()"
```

**Expected output:**
```
✅ DB OK - Backend can reach Database!
```

> 🍔 **"Chef called Storage — 'Do we have ingredients?' Storage: 'Yes!' The kitchen-to-storage door works!"**

---

### Command 45: Test Database → Frontend (Should ❌ FAIL)

```bash
kubectl exec -n three-tier db -- \
  sh -c "wget -qO- --timeout=3 http://frontend-svc:80 || echo '❌ BLOCKED - DB cannot reach Frontend!'"
```

**Expected output:**
```
❌ BLOCKED - DB cannot reach Frontend!
```

> 🍔 **"Storage clerk tried to call reception — BLOCKED! Storage has no keys to go anywhere. Correct!"**

---

# PHASE 13: TEST — Kyverno Security

> 🍔 **"Let's try sneaking past the security guard with fake IDs!"**

---

### Command 46: Try creating a PRIVILEGED container (Should ❌ FAIL)

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

**Expected output (should be an ERROR):**
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/three-tier/test-privileged was blocked due to the following policies:

disallow-privileged-containers:
  deny-privileged: 'Privileged containers are not allowed.'
```

**✅ BLOCKED! Kyverno is working!**

> 🍔 **"Someone tried to enter with an all-access pass. Security guard said NO! 🛑"**

---

### Command 47: Try using :latest image tag (Should ❌ FAIL)

```bash
kubectl run test-latest --image=nginx:latest -n three-tier
```

**Expected output (should be an ERROR):**
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/three-tier/test-latest was blocked due to the following policies:

disallow-latest-tag:
  deny-latest-tag: 'Using ':latest' tag is not allowed.'
```

**✅ BLOCKED!**

---

### Command 48: Try using NO image tag at all (Should ❌ FAIL)

```bash
kubectl run test-notag --image=nginx -n three-tier
```

**Expected output (should be an ERROR):**
```
Error from server: ...
disallow-latest-tag:
  require-image-tag: 'An image tag is required.'
```

**✅ BLOCKED! All 3 security tests pass!**

---

# PHASE 14: TEST — PDB & Node Drain

> 🍔 **"Let's renovate a floor and prove the restaurant stays open!"**

---

### Command 49: Show current PDB status

```bash
kubectl get pdb -n three-tier
```

**Expected output:**
```
NAME           MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
frontend-pdb   1               N/A               1                     10m
backend-pdb    1               N/A               1                     10m
```

---

### Command 50: Find the frontend node name

```bash
FRONTEND_NODE=$(kubectl get nodes -l tier=frontend -o jsonpath='{.items[0].metadata.name}')
echo "Frontend node is: $FRONTEND_NODE"
```

**Expected output:**
```
Frontend node is: k3d-three-tier-agent-0
```

---

### Command 51: Drain the frontend node (start renovation!)

```bash
kubectl drain "$FRONTEND_NODE" --ignore-daemonsets --delete-emptydir-data
```

**What this does:** "Remove all pods from this node — it's going offline for maintenance."

**Expected output:**
```
node/k3d-three-tier-agent-0 cordoned
evicting pod three-tier/frontend-xxxxx-yyyyy
evicting pod three-tier/frontend-xxxxx-zzzzz
pod/frontend-xxxxx-yyyyy evicted
pod/frontend-xxxxx-zzzzz evicted
node/k3d-three-tier-agent-0 drained
```

> 🍔 **"Floor 1 is being renovated. Employees are being moved out one by one."**

---

### Command 52: Check pod status after drain

```bash
kubectl get pods -n three-tier -o wide
```

**Expected output:**
```
NAME                        READY   STATUS    NODE
frontend-xxxxx-yyyyy        0/1     Pending   <none>        ← No frontend node available!
frontend-xxxxx-zzzzz        0/1     Pending   <none>
backend-xxxxx-yyyyy         1/1     Running   k3d-three-tier-agent-1
backend-xxxxx-zzzzz         1/1     Running   k3d-three-tier-agent-1
db                          1/1     Running   k3d-three-tier-agent-2
```

**Frontend pods are `Pending`** because their only node is cordoned (closed for maintenance). Backend and DB are fine!

> 🍔 **"The receptionists are waiting in the hallway — their floor is being renovated. But the kitchen and storage are still running!"**

---

### Command 53: Uncordon the node (finish renovation!)

```bash
kubectl uncordon "$FRONTEND_NODE"
```

**Expected output:**
```
node/k3d-three-tier-agent-0 uncordoned
```

---

### Command 54: Wait and verify everyone comes back

```bash
sleep 15 && kubectl get pods -n three-tier -o wide
```

**Expected output:** All 5 pods `Running` on their correct nodes again!

> 🍔 **"Renovation complete! All employees are back at their desks. Zero customers were permanently lost!"**

---

# PHASE 15: Check Resource Limits

> 🍔 **"Verify every employee has a defined desk size and filing cabinet limit."**

---

### Command 55: Show resources for all pods

```bash
kubectl get pods -n three-tier -o jsonpath='{range .items[*]}{"Pod: "}{.metadata.name}{"\n  Requests: "}{.spec.containers[0].resources.requests}{"\n  Limits:   "}{.spec.containers[0].resources.limits}{"\n\n"}{end}'
```

**Expected output:**
```
Pod: frontend-xxxxx-yyyyy
  Requests: {"cpu":"100m","memory":"64Mi"}
  Limits:   {"cpu":"200m","memory":"128Mi"}

Pod: frontend-xxxxx-zzzzz
  Requests: {"cpu":"100m","memory":"64Mi"}
  Limits:   {"cpu":"200m","memory":"128Mi"}

Pod: backend-xxxxx-yyyyy
  Requests: {"cpu":"100m","memory":"64Mi"}
  Limits:   {"cpu":"200m","memory":"128Mi"}

Pod: backend-xxxxx-zzzzz
  Requests: {"cpu":"100m","memory":"64Mi"}
  Limits:   {"cpu":"200m","memory":"128Mi"}

Pod: db
  Requests: {"cpu":"50m","memory":"32Mi"}
  Limits:   {"cpu":"100m","memory":"64Mi"}
```

**Every pod has requests AND limits. ✅**

---

# PHASE 16: Run the Automated Test Suite

> 🍔 **"Run ALL tests at once and get a report card!"**

---

### Command 56: Make the test script executable

```bash
chmod +x tests/validate.sh
```

---

### Command 57: Run all tests

```bash
./tests/validate.sh
```

**This runs ~20 automated tests and prints PASS/FAIL for each one. Expected final output:**

```
============================================================
  ALL TESTS PASSED: 20/20
============================================================
```

---

# PHASE 17: Cleanup (Tear Down the Building)

> 🍔 **"Close the restaurant and demolish the building."**

---

### Command 58: Delete the entire cluster

```bash
k3d cluster delete three-tier
```

**Expected output:**
```
INFO[0000] Deleting cluster 'three-tier'
INFO[0005] Removing cluster details from default kubeconfig...
INFO[0005] Removing standalone kubeconfig file...
INFO[0005] Successfully deleted cluster three-tier!
```

---

### Command 59: Verify it's gone

```bash
k3d cluster list
```

**Expected output:**
```
NAME   SERVERS   AGENTS   LOADBALANCER
(empty)
```

**Everything is gone. Your laptop is clean. You can recreate it anytime by running from Command 9 again.**

---

# 🏆 QUICK REFERENCE: All Commands in Order

| # | Command | Purpose |
|---|---|---|
| 1-5 | `docker --version` etc. | Check tools |
| 8 | `k3d cluster delete` | Clean start |
| 9 | `k3d cluster create` | Build cluster |
| 10 | `kubectl get nodes` | Verify nodes |
| 12-14 | `kubectl label node` | Label nodes |
| 15 | `kubectl get nodes -L tier` | Verify labels |
| 17 | `kubectl apply -f namespaces.yaml` | Create namespace |
| 20-21 | `kubectl apply -f frontend/` | Deploy frontend |
| 23-24 | `kubectl apply -f backend/` | Deploy backend |
| 25 | `kubectl apply -f db/pod.yaml` | Deploy database |
| 26 | `kubectl get pods -o wide` | **⭐ Verify pods** |
| 29 | `kubectl apply -f pdb/` | Apply PDBs |
| 32 | `kubectl apply -f policies/network-policy.yaml` | Apply firewall |
| 35 | `helm install kyverno` | Install security |
| 38 | `kubectl apply -f policies/kyverno-policies.yaml` | Apply rules |
| 42 | `curl backend-svc` (from frontend) | Test ✅ allowed |
| 43 | `curl db-svc` (from frontend) | Test ❌ blocked |
| 46 | `kubectl run --privileged` | Test ❌ blocked |
| 47 | `kubectl run --image=:latest` | Test ❌ blocked |
| 51 | `kubectl drain` | Test PDB |
| 57 | `./tests/validate.sh` | Run all tests |
| 58 | `k3d cluster delete` | Cleanup |

**Or just use the shortcut:**
```bash
chmod +x cluster-setup.sh && ./cluster-setup.sh    # Commands 8-39 in one shot!
chmod +x tests/validate.sh && ./tests/validate.sh  # Commands 40-55 in one shot!
```

---

**🎉 You now understand every single command in this project!**
