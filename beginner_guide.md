# 🍔 The Complete K3d 3-Tier Project Guide
## (Taught Like You're 5, But With Real-World Scenarios)

---

# 🏢 THE BIG PICTURE: Your Project = A Food Delivery Company

Imagine you're the **CEO of "QuickBite"** — a food delivery company like **Zomato or Swiggy**.

Your company has **3 departments**:

```
╔══════════════════════════════════════════════════════════════╗
║                    🏢 QuickBite HQ                          ║
║                                                              ║
║  🏬 FLOOR 1              🏭 FLOOR 2           🗄️ FLOOR 3    ║
║  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐  ║
║  │  CUSTOMER      │  │   KITCHEN      │  │  STORAGE     │  ║
║  │  SERVICE DESK  │  │   (Cooking)    │  │  ROOM        │  ║
║  │                │  │                │  │              │  ║
║  │ • Takes orders │  │ • Makes food   │  │ • Stores     │  ║
║  │ • Shows menu   │  │ • Processes    │  │   ingredients│  ║
║  │ • Talks to     │  │   orders       │  │ • Only       │  ║
║  │   kitchen      │  │ • Gets items   │  │   kitchen    │  ║
║  │                │  │   from storage  │  │   can access │  ║
║  └────────────────┘  └────────────────┘  └──────────────┘  ║
║                                                              ║
║  Customer Desk → Kitchen ✅    Kitchen → Storage ✅          ║
║  Customer Desk → Storage ❌    Storage → Anyone ❌           ║
╚══════════════════════════════════════════════════════════════╝
```

**Now here's the key mapping:**

| Real World (QuickBite) | Your Kubernetes Project |
|---|---|
| The entire company building | **The Kubernetes Cluster** |
| The CEO's office (manages everything) | **Control Plane (Server node)** |
| Floor 1 (Customer Service) | **Worker Node with label `tier=frontend`** |
| Floor 2 (Kitchen) | **Worker Node with label `tier=backend`** |
| Floor 3 (Storage) | **Worker Node with label `tier=db`** |
| Customer service employees | **Frontend Pods (nginx)** |
| Kitchen chefs | **Backend Pods (Python API)** |
| Storage room clerk | **Database Pod (busybox)** |
| The company name "QuickBite" | **Namespace `three-tier`** |
| Employee ID badges | **Labels** |
| Building security guards | **Kyverno policies** |
| Door locks between floors | **Network Policies** |
| "Keep minimum 1 chef on duty" rule | **PodDisruptionBudget** |
| Hiring a replacement when someone quits | **Deployment (self-healing)** |
| The reception desk phone number | **Service (ClusterIP)** |

Let me teach you every single part using this analogy. After each section, I'll show you the actual code.

---

# 📖 CHAPTER 1: What is Docker, k3d, and Kubernetes?

## Real-World Scenario

Imagine you want to send a **gift box** to 10 different people. Each gift box must contain:
- 1 chocolate
- 1 toy
- 1 card

### Without Docker (The Old Way):
You go to each person's house, buy chocolates locally (different brands each time), find a toy (different shops), write a card... Every gift is **different** because each location has different stuff available.

### With Docker (The New Way):
You create ONE perfect gift box. You **photograph every detail** — exact chocolate brand, exact toy, exact card. Now you can recreate this EXACT same gift box **anywhere in the world**. The photograph = **Docker Image**. The actual gift box = **Docker Container**.

```
Docker Image  = The recipe/blueprint (e.g., "nginx:1.25.4")
Docker Container = The actual running thing made from that recipe
```

### What is Kubernetes?

Now imagine you're not sending 1 gift box — you're sending **10,000 gift boxes daily** for your business.

You need someone to:
- Make sure all boxes are prepared ✅
- If a box breaks, make a new one ✅
- If demand increases, make more boxes ✅
- If a worker is sick, reassign their work ✅

**Kubernetes is that manager.** It's an automated system that manages your containers (gift boxes).

### What is k3d?

**Real scenario:** Building a real Kubernetes cluster needs multiple physical servers. That's expensive! 

**k3d** = "Kubernetes in Docker" — it creates **fake servers (nodes) using Docker containers** on your laptop. It's like building a **mini model of your company building** on your desk to practice before building the real thing.

```
Real Production:  10 physical servers in a data center   → $$$$
Your Laptop (k3d): 4 Docker containers pretending to be servers → FREE
```

---

# 📖 CHAPTER 2: The Cluster — Your Company Building

## Real-World Scenario

You're building QuickBite's office. You need:
- **1 Manager's Office** (control plane) — doesn't do actual food work, just manages everyone
- **3 Work Floors** (worker nodes) — where actual work happens

## The Code: `cluster-setup.sh` (Lines 57-62)

```bash
k3d cluster create "three-tier" \
  --servers 1 \       # 1 manager's office (control plane)
  --agents 3 \        # 3 work floors (worker nodes)
  --k3s-arg "--disable=traefik@server:*" \  # Don't install default routing
  --wait              # Wait until building is ready
```

**Line by line:**

| Code | QuickBite Analogy |
|---|---|
| `k3d cluster create "three-tier"` | "Build a company building named 'three-tier'" |
| `--servers 1` | "1 manager's office" |
| `--agents 3` | "3 working floors" |
| `--k3s-arg "--disable=traefik@server:*"` | "Don't install the default reception system, we'll handle it ourselves" |
| `--wait` | "Don't give me the keys until construction is done" |

**After this command runs, you have:**

```
┌────────────────────────────────────────────┐
│           k3d Cluster: "three-tier"         │
│                                              │
│  ┌────────────────────┐                      │
│  │ k3d-three-tier-     │  ← Manager's office │
│  │ server-0 (CONTROL)  │    (doesn't run apps)│
│  └────────────────────┘                      │
│                                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────┐│
│  │ agent-0     │ │ agent-1     │ │ agent-2 ││
│  │ (Floor 1)   │ │ (Floor 2)   │ │ (Floor 3)│
│  │ EMPTY       │ │ EMPTY       │ │ EMPTY   ││
│  └─────────────┘ └─────────────┘ └─────────┘│
└────────────────────────────────────────────┘
```

Right now the floors are **empty** — no labels, no employees, nothing. Let's fix that.

---

# 📖 CHAPTER 3: Namespaces — The Company Name on the Door

## Real-World Scenario

Imagine a **shared office building** where multiple companies work:
- Floor 1-3: **QuickBite** (that's us!)
- Floor 4-5: **SpeedPost** (a courier company)
- Floor 6: **CloudBytes** (an IT company)

Each company has its own **nameplate on the door** so mail, visitors, and supplies go to the right company. No mix-ups!

**A namespace is that nameplate.** It keeps your stuff separated from everyone else's stuff.

## The Code: `namespaces.yaml`

```yaml
apiVersion: v1          # "I'm using version 1 of the Kubernetes API"
kind: Namespace         # "I want to create a Namespace"
metadata:
  name: three-tier      # "Call it 'three-tier' — that's our company name"
  labels:
    name: three-tier    # "Put a label on it too"
```

**Why do we need this?**

Without a namespace, your pods go into the `default` namespace — like an employee without a department. It works, but it's messy. Using `three-tier` namespace means:

```bash
# Only see OUR stuff, not everyone else's
kubectl get pods -n three-tier

# Without namespace, you'd see EVERYONE'S pods — confusing!
kubectl get pods --all-namespaces
```

---

# 📖 CHAPTER 4: Node Labels — Department Signs on Each Floor

## Real-World Scenario

Remember your 3 empty floors? Now you need to put **signs** on each floor:

```
Floor 1 → Sign: "CUSTOMER SERVICE DEPARTMENT"  (tier=frontend)
Floor 2 → Sign: "KITCHEN DEPARTMENT"           (tier=backend)
Floor 3 → Sign: "STORAGE DEPARTMENT"           (tier=db)
```

Without these signs, new employees wouldn't know which floor to go to!

## The Code: `cluster-setup.sh` (Lines 79-81)

```bash
kubectl label node k3d-three-tier-agent-0 tier=frontend --overwrite
kubectl label node k3d-three-tier-agent-1 tier=backend  --overwrite
kubectl label node k3d-three-tier-agent-2 tier=db       --overwrite
```

**Breaking it down:**

| Part | Meaning |
|---|---|
| `kubectl` | "Hey Kubernetes..." |
| `label` | "...put a sticky note on..." |
| `node k3d-three-tier-agent-0` | "...this floor (agent-0)..." |
| `tier=frontend` | "...that says 'tier=frontend'" |
| `--overwrite` | "...and if there's already a note, replace it" |

**After labeling:**

```
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ agent-0         │ │ agent-1         │ │ agent-2         │
│ 🏷️ tier=frontend│ │ 🏷️ tier=backend │ │ 🏷️ tier=db      │
│ "Customer Svc"  │ │ "Kitchen"       │ │ "Storage Room"  │
│ STILL EMPTY     │ │ STILL EMPTY     │ │ STILL EMPTY     │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

**How to verify:**

```bash
kubectl get nodes --show-labels
```

You'll see something like:
```
NAME                        STATUS   LABELS
k3d-three-tier-agent-0      Ready    tier=frontend,...
k3d-three-tier-agent-1      Ready    tier=backend,...
k3d-three-tier-agent-2      Ready    tier=db,...
k3d-three-tier-server-0     Ready    node-role.kubernetes.io/control-plane=true,...
```

---

# 📖 CHAPTER 5: Deployments & Pods — Hiring Employees

## Real-World Scenario

Now let's **hire employees** for each department:

- **Customer Service Desk:** Hire 2 receptionists (in case one calls in sick)
- **Kitchen:** Hire 2 chefs (in case one takes a break)
- **Storage:** Hire 1 clerk (low workload, 1 is enough)

### What's a Pod?

A **Pod** = One employee at their desk, doing their job.

```
Pod = Raju sitting at the customer service desk, answering phones
```

### What's a Deployment?

A **Deployment** = The **HR Manager** who:
- Hires the right number of employees (replicas)
- If someone quits, **immediately hires a replacement**
- If you say "I need 5 chefs now instead of 2", scales up instantly

```
                    HR Manager (Deployment)
                    ┌────────────────────┐
                    │ "I need 2 chefs"   │
                    │ "If one quits,     │
                    │  hire a new one"   │
                    └────┬──────────┬────┘
                         │          │
                    ┌────▼────┐ ┌──▼──────┐
                    │ Chef    │ │ Chef    │
                    │ Raju    │ │ Priya   │
                    │ (Pod 1) │ │ (Pod 2) │
                    └─────────┘ └─────────┘
```

**Real scenario showing why Deployments matter:**

```
SCENARIO: Chef Raju gets food poisoning 🤮

WITHOUT Deployment (raw Pod):
   Raju's pod dies → Nobody replaces him → Kitchen is short-staffed → DISASTER

WITH Deployment:
   Raju's pod dies → HR Manager notices → Immediately hires new chef → Kitchen keeps running
   (Kubernetes creates a new Pod automatically)
```

## The Code: `frontend/deployment.yaml` — Hiring 2 Receptionists

Let me explain EVERY line like you've never seen YAML before:

```yaml
apiVersion: apps/v1
```
☝️ **"Which language am I speaking?"** — Telling Kubernetes "I'm using the apps/v1 version of your API." Think of it like saying "I'm writing in English, version 2024."

```yaml
kind: Deployment
```
☝️ **"What am I creating?"** — "I want an HR Manager (Deployment), not just a single employee (Pod)."

```yaml
metadata:
  name: frontend
  namespace: three-tier
  labels:
    app: frontend
    tier: frontend
```
☝️ **"What's its identity?"**
- `name: frontend` → "This HR Manager handles the 'frontend' department"
- `namespace: three-tier` → "This is for QuickBite company"
- `labels` → "Put these ID badges on it: app=frontend, tier=frontend"

**Real World:** Every employee at QuickBite has a badge that says their department. Labels are those badges.

```yaml
spec:
  replicas: 2
```
☝️ **"How many employees do I need?"** → "Hire 2 receptionists"

**Why 2?** If Priya goes on lunch break, Raju is still at the desk. Customers never wait! This is called **High Availability**.

```yaml
  selector:
    matchLabels:
      app: frontend
```
☝️ **"Which employees belong to me?"** → "Any employee wearing a badge that says `app=frontend` is MY employee."

This is how the HR Manager (Deployment) knows which Pods it manages. If it sees a Pod without this badge, it ignores it (not my employee).

```yaml
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
```
☝️ **"When I hire new employees, give them these badges."** → Every new Pod gets `app=frontend` and `tier=frontend` labels.

```yaml
    spec:
      nodeSelector:
        tier: frontend
```
☝️ **🎯 THIS IS THE SCHEDULING RULE!**

**Real World:** "Dear HR, when you hire receptionists, put them on **Floor 1 ONLY** — the floor with the sign 'Customer Service'."

**Technical:** The scheduler reads this and says:
```
Let me find a node with label tier=frontend...
  - agent-0: tier=frontend ✅ → PUT THE POD HERE!
  - agent-1: tier=backend  ❌
  - agent-2: tier=db       ❌
```

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
                      values:
                        - frontend
                topologyKey: kubernetes.io/hostname
```
☝️ **🎯 THIS IS THE ANTI-AFFINITY RULE!**

**Real World Scenario:**

You have 2 receptionists: Raju and Priya. You want them on **different desks** (different machines) so that if one desk breaks, the other still works.

```
ANTI-AFFINITY says:
"Hey scheduler, if Raju (app=frontend) is already on agent-0,
 TRY to put Priya (app=frontend) on a DIFFERENT node."

But wait — we only have ONE frontend node (agent-0)!

That's why it says "preferred" (try your best) not "required" (must do it).
So both Raju and Priya sit on agent-0, and that's okay.

If we later add agent-3 with tier=frontend, Kubernetes would
automatically spread them: Raju on agent-0, Priya on agent-3.
```

Think of it like:
```
"preferred" = "If possible, don't sit next to each other. But if there's only
               one table, it's fine to share."

"required"  = "You MUST sit at different tables! If there's only one table,
               one of you doesn't get to sit (Pending forever)."
```

```yaml
      containers:
        - name: nginx
          image: nginx:1.25.4
```
☝️ **"What software does this employee use?"**

- `name: nginx` → The employee's workstation is called "nginx"
- `image: nginx:1.25.4` → They use nginx version 1.25.4 (a web server software)

**Real World:** "Give the receptionist a computer with version 1.25.4 of our customer service software. NOT the latest version — that one has bugs!"

```yaml
          ports:
            - containerPort: 80
```
☝️ **"Which door can people knock on?"** → "Customers can reach this receptionist through door number 80."

Port 80 = the standard HTTP web port. When you visit any website, your browser talks on port 80 (or 443 for HTTPS).

```yaml
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
```
☝️ **"Is this employee alive?"**

**Real World:** Every few seconds, the manager walks to the desk and asks "Raju, are you alive?" by poking the `/` endpoint on port 80. If Raju doesn't respond 3 times in a row... restart his computer (kill and recreate the container).

`initialDelaySeconds: 5` = "Wait 5 seconds after Raju sits down before checking. Give him time to open his software."

```yaml
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
```
☝️ **"Is this employee READY to work?"**

**Real World:** There's a difference between "alive" and "ready":
- **Alive** = Raju is at his desk, breathing 😤
- **Ready** = Raju has logged into his computer, opened the software, and is ready to take calls 📞

If Raju is alive but NOT ready (still loading his software), Kubernetes won't send customers to him yet.

```yaml
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
```
☝️ **"How much office space and equipment does this employee need?"**

**Real World Scenario:**

```
REQUESTS = "What I need to start working"
   cpu: 100m    → "I need a desk that's at least 10% of a full office" (100 millicores = 0.1 CPU)
   memory: 64Mi → "I need at least 1 small filing cabinet"

LIMITS = "The maximum I'm allowed to use"
   cpu: 200m    → "Even if I'm super busy, I can't take more than 20% of the office"
   memory: 128Mi → "I get maximum 2 filing cabinets. No more!"
```

**Why limits matter:**

```
WITHOUT LIMITS:
   Raju's software has a memory leak → Uses ALL the RAM → 
   EVERY other employee's computer crashes → ENTIRE FLOOR DOWN! 💀

WITH LIMITS:
   Raju's software has a memory leak → Hits 128Mi limit → 
   ONLY Raju's container is killed → Everyone else keeps working ✅
```

This is called the **"noisy neighbor" problem** — one bad container shouldn't affect others.

---

# 📖 CHAPTER 6: Services — The Reception Desk Phone Number

## Real-World Scenario

**Problem:** Employees (pods) can be fired and replaced anytime. Each new employee gets a **new desk phone number** (IP address). How do other departments reach them?

**Scenario:**

```
Monday:
   Raju (Pod) is at desk 10.42.0.15 → Kitchen calls 10.42.0.15 to send orders

Tuesday:
   Raju quits! New hire Amit (Pod) sits at desk 10.42.0.99
   Kitchen still calls 10.42.0.15 → NOBODY ANSWERS! 💀
```

**Solution: A Service = A permanent reception desk number that never changes.**

```
Service "frontend-svc" has permanent number → 10.43.0.100
   ↓
   Routes to whoever is currently at the desk:
   Monday:  10.43.0.100 → Raju  (10.42.0.15) ✅
   Tuesday: 10.43.0.100 → Amit  (10.42.0.99) ✅
   
   The caller doesn't know (or care) who's actually answering!
```

## The Code: `frontend/service.yaml`

```yaml
apiVersion: v1
kind: Service              # "I'm creating a phone directory entry"
metadata:
  name: frontend-svc       # The permanent name everyone uses
  namespace: three-tier
spec:
  type: ClusterIP          # Only reachable from inside the building (cluster)
  selector:
    app: frontend          # "Route calls to anyone wearing a 'frontend' badge"
  ports:
    - port: 80             # "Callers dial port 80"
      targetPort: 80       # "Forward to the employee's port 80"
```

**Now other pods can always reach frontend by calling `frontend-svc:80` — no matter which pod is actually running!**

| Service Name | What it points to | Port |
|---|---|---|
| `frontend-svc` | All pods with `app=frontend` label | 80 |
| `backend-svc` | All pods with `app=backend` label | 8080 |
| `db-svc` | All pods with `app=db` label | 3306 |

---

# 📖 CHAPTER 7: The Database Pod — The Storage Room Clerk

## Real-World Scenario

The storage room only needs **1 clerk**. They don't need fancy software — just a walkie-talkie (port 3306) to say "ingredients ready!" when the kitchen asks.

## The Code: `db/pod.yaml`

```yaml
apiVersion: v1
kind: Pod               # ← Direct Pod, NOT a Deployment!
metadata:
  name: db
  namespace: three-tier
  labels:
    app: db
    tier: db
spec:
  nodeSelector:
    tier: db             # "Put me on Floor 3 (Storage)"
  containers:
    - name: db
      image: busybox:1.36
      command: ["sh", "-c", 
        "while true; do echo -e 'HTTP/1.1 200 OK\r\n\r\nDB OK' | nc -l -p 3306; done & sleep infinity"]
```

**What does that command do?** Let me break it down:

```
while true; do                    # "Keep doing this forever..."
  echo 'DB OK'                   #   "Say 'DB OK'"
  | nc -l -p 3306;              #   "...on port 3306 to whoever calls"
done                             # "...then loop again"
& sleep infinity                 # "Also keep the container alive forever"
```

**Real World:** It's like a clerk who answers the warehouse phone saying "We have ingredients!" every time someone calls. It's a **dummy** — in a real project, this would be MySQL or PostgreSQL.

**Why Pod and not Deployment?** The assignment says "dummy pod." Since it's not a real database, we don't need HR Manager (Deployment) to replace it if it dies.

---

# 📖 CHAPTER 8: Network Policies — Door Locks Between Floors

## Real-World Scenario: The Security Incident 🚨

**Before Network Policies:**

```
Week 1: Everything works fine. Kitchen sends orders to storage, gets ingredients.

Week 2: A hacker gets into the FRONTEND pod (customer service desk).
         Without network policies, the hacker can directly access the DATABASE!
         
         Hacker: "I'm in the customer desk... let me just call the storage room..."
         Storage: "Sure! Here's all the customer credit card data!" 💀
         
         THE ENTIRE DATABASE IS COMPROMISED THROUGH THE FRONTEND!
```

**After Network Policies (Zero-Trust):**

```
Step 1: LOCK ALL DOORS. Nobody can go anywhere.
Step 2: Give specific keys to specific people:
         - Reception has a key to Kitchen door ✅
         - Kitchen has a key to Storage door ✅
         - Reception does NOT have a key to Storage door ❌
         - Storage has NO keys at all (can't go anywhere) ❌

Now if a hacker gets into the frontend:
         Hacker: "I'm in the customer desk... let me call storage..."
         🚪 *DOOR LOCKED* — No key! ❌
         Hacker: "Fine, let me go to kitchen..."
         Kitchen: *still safe — hacker can reach it but can't escalate to DB*
```

## The Code: `policies/network-policy.yaml`

### Policy 1: Lock All Doors (Default Deny)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: three-tier
spec:
  podSelector: {}         # {} = ALL pods in this namespace
  policyTypes:
    - Ingress             # Block all incoming traffic
    - Egress              # Block all outgoing traffic
```

**Real World:** "Effective immediately, ALL doors in the building are LOCKED. Nobody can call anybody, nobody can visit anybody."

```
BEFORE default-deny:        AFTER default-deny:
Frontend ↔ Backend ✅       Frontend → Backend ❌
Frontend ↔ DB ✅            Frontend → DB ❌
Backend ↔ DB ✅             Backend → DB ❌
Everyone ↔ Everyone ✅      EVERYTHING ❌❌❌
```

### Policy 2: Allow DNS (The Phone Book)

```yaml
spec:
  podSelector: {}          # All pods
  policyTypes:
    - Egress               # Allow OUTGOING traffic
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53          # DNS port
```

**Real World:** "Wait — we locked ALL doors. Now nobody can even use the phone book to look up extensions! Fix: Allow everyone to use the company phone directory (DNS on port 53)."

Without this policy:
```
Frontend: "Hey, what's the phone number for backend-svc?"
DNS: *silence* (blocked!)
Frontend: "I CAN'T FIND THE KITCHEN! EVERYTHING IS BROKEN!"
```

### Policies 3-4: Customer Service → Kitchen (Key Given)

```yaml
# Policy 3: Frontend CAN SEND to Backend
spec:
  podSelector:
    matchLabels:
      app: frontend       # "This key is for: Customer Service staff"
  policyTypes:
    - Egress              # "They can GO OUT..."
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: backend  # "...to the Kitchen"
      ports:
        - protocol: TCP
          port: 8080       # "...through door 8080"

# Policy 4: Backend CAN RECEIVE from Frontend  
spec:
  podSelector:
    matchLabels:
      app: backend        # "This door rule is for: Kitchen"
  policyTypes:
    - Ingress             # "The Kitchen door..."
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend  # "...opens for Customer Service staff"
      ports:
        - protocol: TCP
          port: 8080
```

**Real World:** You need **2 things** for someone to visit another floor:
1. **Exit pass** (Egress policy) — "You're allowed to LEAVE your floor"
2. **Entry pass** (Ingress policy) — "The other floor ALLOWS you to enter"

Without BOTH, the visit fails:
```
Egress but no Ingress: You can leave your floor... but Kitchen's door is locked 🔒
Ingress but no Egress: Kitchen unlocked... but you can't leave your floor 🔒
BOTH: You leave your floor AND Kitchen lets you in ✅
```

### Policies 5-6: Kitchen → Storage (Key Given)

Same pattern: Backend gets egress to DB, DB gets ingress from Backend.

### What's NOT in the policies:

```
❌ No "frontend egress to db" policy
❌ No "db ingress from frontend" policy
❌ No "db egress to anyone" policy

So these paths are BLOCKED:
   Frontend → Database  ❌ (no key)
   Database → Frontend  ❌ (no key)
   Database → Backend   ❌ (no key)
```

---

# 📖 CHAPTER 9: Kyverno — The Security Guard at the Main Gate

## Real-World Scenario: The New Employee Problem 🚨

```
STORY 1: The Dangerous Employee

HR wants to hire a new employee with "ADMIN ACCESS TO EVERYTHING" (privileged: true).

WITHOUT Kyverno:
   HR: "Here's a new employee with all-access pass!"
   System: "Sure, welcome!" ← 💀 This employee can access ANYTHING

WITH Kyverno:
   HR: "Here's a new employee with all-access pass!"
   Security Guard (Kyverno): "🛑 STOP! Company policy says 
   NO ONE gets all-access passes. REJECTED!"
   
   The employee never enters the building.
```

```
STORY 2: The Mystery Software

HR wants to install software version "latest" (you don't know exactly what version that is).

WITHOUT Kyverno:
   HR: "Install nginx:latest on Raju's computer!"
   System: "Done!" ← But what version is "latest"? Today it's 1.26, 
   tomorrow it might be 2.0 which breaks everything!

WITH Kyverno:
   HR: "Install nginx:latest!"
   Security Guard (Kyverno): "🛑 STOP! You must specify an EXACT version 
   like nginx:1.25.4. 'latest' is forbidden!"
```

## The Code: `policies/kyverno-policies.yaml`

### Policy 1: No All-Access Passes (No Privileged Containers)

```yaml
spec:
  validationFailureAction: Enforce    # "BLOCK it, don't just warn"
  rules:
    - name: deny-privileged
      match:
        any:
          - resources:
              kinds:
                - Pod             # Check every new Pod
      validate:
        message: "Privileged containers are not allowed."
        pattern:
          spec:
            containers:
              - =(securityContext):       # "If there's a security section..."
                  =(privileged): "false"  # "...privileged MUST be false"
```

**The `=(...)` syntax means "if this field exists, it must match."** If `securityContext` doesn't exist, that's fine (no danger). If it exists AND has `privileged: true`, BLOCKED!

### Policy 2: No "latest" Software (No :latest Tag)

```yaml
# Sub-rule 1: Every image MUST have a version tag
validate:
  pattern:
    spec:
      containers:
        - image: "*:*"       # Must match "something:something"
                              # "nginx" alone = ❌ (no tag)
                              # "nginx:latest" = passes this rule (has a tag)
                              # "nginx:1.25.4" = passes this rule ✅

# Sub-rule 2: The tag cannot be "latest"  
validate:
  foreach:
    - list: "request.object.spec.containers"  # Check EACH container
      deny:
        conditions:
          any:
            - key: "{{ element.image }}"      # "Look at the image name..."
              operator: Equals
              value: "*:latest"               # "...if it ends with :latest, DENY!"
```

**Together:**
```
nginx          → ❌ (no tag — fails rule 1)
nginx:latest   → ❌ (has tag, but it's "latest" — fails rule 2)
nginx:1.25.4   → ✅ (has a specific tag)
```

---

# 📖 CHAPTER 10: PDB — The "Minimum Staff" Rule

## Real-World Scenario: The Renovation Problem 🏗️

```
SCENARIO: The building owner wants to renovate Floor 1 (frontend node).
          He needs to temporarily close the floor and move everyone out.

WITHOUT PDB:
   Building Owner: "Everyone on Floor 1, GET OUT NOW! All at once!"
   [All 2 receptionists leave simultaneously]
   [Customer Service Desk is EMPTY for 10 minutes during renovation]
   [Customers arrive — NOBODY IS THERE! Revenue lost! 💀]

WITH PDB (minAvailable: 1):
   Building Owner: "I need to renovate Floor 1."
   PDB Rule: "You must keep at least 1 receptionist available at all times."
   
   Building Owner: "OK, I'll move Priya first."
   [Priya moves out → Raju is still at the desk ✅]
   [Customers still have service!]
   
   [After Priya is set up on a temporary desk...]
   Building Owner: "Now move Raju."
   [Raju moves out → Priya is on the temp desk ✅]
   [Customers STILL have service!]
   
   ZERO DOWNTIME! 🎉
```

## The Code: `pdb/frontend-pdb.yaml`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: three-tier
spec:
  minAvailable: 1            # "At least 1 must stay running"
  selector:
    matchLabels:
      app: frontend          # "This rule applies to frontend pods"
```

**When does this kick in?**

```bash
kubectl drain <node-name>    # "Evacuate this floor for maintenance"
```

**The math:**
```
You have: 2 frontend pods
PDB says: minAvailable = 1
So: allowed disruptions = 2 - 1 = 1

Kubernetes can evict: 1 pod at a time (not both!)
```

---

# 📖 CHAPTER 11: `cluster-setup.sh` — The One Script That Does EVERYTHING

## Real-World Scenario

Instead of manually:
1. Building the office
2. Putting up department signs
3. Hiring employees
4. Installing door locks
5. Hiring security guards
6. ...

You have **ONE magic button** that does it ALL. That's `cluster-setup.sh`.

## What each section does:

```
cluster-setup.sh
│
├─ Step 1:  "Are my tools installed?" (docker, k3d, kubectl, helm)
│           Real world: "Do I have a hammer, nails, paint, and brushes?"
│
├─ Step 2:  "Build the building" (k3d cluster create)
│           Real world: "Construct 1 manager office + 3 floors"
│
├─ Step 3:  "Put department signs" (kubectl label node)
│           Real world: "Floor 1 = Customer Service, Floor 2 = Kitchen..."
│
├─ Step 4:  "Name the company" (kubectl apply -f namespaces.yaml)
│           Real world: "Put 'QuickBite' nameplate on the door"
│
├─ Step 5:  "Hire employees" (kubectl apply -f frontend/ backend/ db/)
│           Real world: "Hire 2 receptionists, 2 chefs, 1 clerk"
│
├─ Step 6:  "Set minimum staff rules" (kubectl apply -f pdb/)
│           Real world: "Always keep at least 1 person per department"
│
├─ Step 7:  "Install door locks" (kubectl apply -f policies/network-policy.yaml)
│           Real world: "Lock all doors, then give specific keys"
│
├─ Step 8:  "Hire security guard" (helm install kyverno + apply policies)
│           Real world: "Hire a guard at the gate who checks everyone"
│
├─ Step 9:  "Wait for everyone to be ready"
│           Real world: "Wait until all employees have logged in"
│
├─ Step 10: "Run safety inspection" (Trivy scan — optional)
│           Real world: "Check if the software has known vulnerabilities"
│
└─ Step 11: "Print summary" (show who's where)
            Real world: "Here's your employee directory!"
```

---

# 📖 CHAPTER 12: TESTING — Proving Everything Works

## Test 1: Are employees on the right floors?

```bash
kubectl get pods -n three-tier -o wide
```

**What you see:**
```
NAME                       READY   STATUS    NODE
frontend-abc12-xyz34       1/1     Running   k3d-three-tier-agent-0  ← ✅ Frontend floor!
frontend-abc12-pqr56       1/1     Running   k3d-three-tier-agent-0  ← ✅ Frontend floor!
backend-def45-xyz78        1/1     Running   k3d-three-tier-agent-1  ← ✅ Backend floor!
backend-def45-mno90        1/1     Running   k3d-three-tier-agent-1  ← ✅ Backend floor!
db                         1/1     Running   k3d-three-tier-agent-2  ← ✅ DB floor!
```

**Real World:** "Is Raju at the customer desk? Is the chef in the kitchen? Is the clerk in storage? YES! ✅"

---

## Test 2: Can Customer Service call the Kitchen?

```bash
# "Receptionist, try calling the Kitchen on port 8080"
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "apt-get update -qq > /dev/null 2>&1 && \
         apt-get install -y -qq curl > /dev/null 2>&1 && \
         curl -s --max-time 5 http://backend-svc:8080"
```

**Expected output:** HTML directory listing (the Python http.server response)

**Real World:** "Receptionist picks up phone → dials Kitchen extension → Kitchen answers! ✅"

---

## Test 3: Can Customer Service call Storage directly?

```bash
# "Receptionist, try calling the Storage Room directly"
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "curl -s --max-time 5 http://db-svc:3306 || echo 'BLOCKED!'"
```

**Expected output:** `BLOCKED!` (or timeout)

**Real World:** "Receptionist picks up phone → dials Storage extension → 🔒 LOCKED! No direct line! ❌"

---

## Test 4: Can the Kitchen call Storage?

```bash
# "Chef, try calling the Storage Room"
kubectl exec -n three-tier deploy/backend -- \
  python -c "import socket; s=socket.socket(); s.settimeout(5); s.connect(('db-svc', 3306)); print('DB OK'); s.close()"
```

**Expected output:** `DB OK`

**Real World:** "Chef picks up phone → dials Storage → Storage answers 'Ingredients ready!' ✅"

---

## Test 5: Can someone enter with an All-Access pass?

```bash
# "Security guard, someone is trying to enter with ADMIN ACCESS!"
kubectl run test-privileged --image=nginx:1.25.4 -n three-tier \
  --overrides='{"spec":{"containers":[{"name":"test","image":"nginx:1.25.4","securityContext":{"privileged":true}}]}}'
```

**Expected output:** Error containing "Privileged containers are not allowed"

**Real World:** "Person at the gate: 'I have an all-access pass!' Security Guard: 'Sorry, company policy. NO all-access passes allowed. Please leave.' 🛑"

---

## Test 6: Can someone install mystery software?

```bash
# "Someone is trying to install software without a version number!"
kubectl run test-latest --image=nginx:latest -n three-tier
```

**Expected output:** Error containing "Using ':latest' tag is not allowed"

**Real World:** "IT request: 'Install whatever the newest version is.' IT Security: 'No! You must specify exactly which version. We need to know what's running!' 🛑"

---

## Test 7: Does the Minimum Staff rule work?

```bash
# Step 1: Which floor is the frontend on?
FRONTEND_NODE=$(kubectl get nodes -l tier=frontend -o jsonpath='{.items[0].metadata.name}')

# Step 2: Try to renovate that floor (drain the node)
kubectl drain "$FRONTEND_NODE" --ignore-daemonsets --delete-emptydir-data

# Step 3: Check what happened
kubectl get pods -n three-tier -o wide
# Pods should be evicted ONE at a time, not all at once

# Step 4: Reopen the floor
kubectl uncordon "$FRONTEND_NODE"

# Step 5: Wait and verify everyone's back
sleep 15
kubectl get pods -n three-tier -o wide
# All pods should be Running again
```

**Real World:** 
```
Building Owner: "I need to renovate Floor 1!"
PDB: "Fine, but keep at least 1 receptionist on duty."
Owner: "OK, moving Priya first... [done]... Raju is still here ✅"
Owner: "Now Raju... [done]."
Owner: "Renovation complete! Everyone back to Floor 1!"
[All employees return to their desks]
```

---

# 📖 CHAPTER 13: The Complete Run Order

## From Zero to Working Project:

```bash
# 1. Open Git Bash (not PowerShell!)
# 2. Navigate to your project
cd /e/Abluva/k3d-3tier

# 3. Make scripts executable
chmod +x cluster-setup.sh
chmod +x tests/validate.sh
chmod +x security/trivy-scan.sh

# 4. Run the magic button (takes ~5 minutes)
./cluster-setup.sh

# 5. Verify everything
./tests/validate.sh

# 6. (Optional) Scan for vulnerabilities
./security/trivy-scan.sh

# 7. When done, destroy everything
k3d cluster delete three-tier
```

---

# 📖 CHAPTER 14: Interview Demo Script (Word by Word)

## The 5-Minute Presentation

### Opening (15 seconds)

> "I've built a secure 3-tier application topology on a local Kubernetes cluster using k3d. The project demonstrates workload isolation, zero-trust networking, policy enforcement, and resilience — all concepts used in production environments."

### Show the Architecture (45 seconds)

```bash
kubectl get nodes --show-labels | grep tier
```

> "I have 3 worker nodes, each labeled for a specific tier. Agent-0 handles frontend workloads, Agent-1 handles backend, and Agent-2 handles database. This is called **workload isolation** — in production, you'd separate tiers to prevent resource contention and limit blast radius during failures."

### Show Pod Placement (30 seconds)

```bash
kubectl get pods -n three-tier -o wide
```

> "Using `nodeSelector`, each pod is pinned to its designated node. I also have `podAntiAffinity` configured so that if I add more nodes to a tier, replicas will automatically spread across them for high availability."

### Demonstrate Network Security (90 seconds)

```bash
# Allowed path
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "curl -s --max-time 3 http://backend-svc:8080 | head -5"
```

> "Here I'm proving the frontend CAN reach the backend — this is the allowed traffic path."

```bash
# Blocked path
kubectl exec -n three-tier deploy/frontend -- \
  sh -c "curl -s --max-time 3 http://db-svc:3306 || echo 'BLOCKED'"
```

> "But the frontend CANNOT reach the database directly. I've implemented a **zero-trust network model** — all traffic is denied by default, and I explicitly whitelist only the paths that should exist: frontend-to-backend and backend-to-database."

### Demonstrate Policy Enforcement (45 seconds)

```bash
kubectl run demo-priv --image=nginx:1.25.4 -n three-tier \
  --overrides='{"spec":{"containers":[{"name":"x","image":"nginx:1.25.4","securityContext":{"privileged":true}}]}}'
```

> "I'm using Kyverno as an admission controller. It blocks privileged containers and images using the `:latest` tag. This is a **shift-left security approach** — we prevent misconfigurations before they enter the cluster, rather than detecting them after."

### Show Resilience (30 seconds)

```bash
kubectl get pdb -n three-tier
```

> "Finally, I have PodDisruptionBudgets ensuring that during node maintenance or cluster upgrades, at least one pod per tier remains available. Combined with 2 replicas per tier, this gives us zero-downtime operations."

### Closing (15 seconds)

> "The entire setup is automated via a single shell script and validated with an automated test suite. Everything is reproducible from scratch in under 5 minutes."

---

# 📖 CHAPTER 15: Common Mistakes & Debugging

| What You See | What It Means (Real World) | How to Fix |
|---|---|---|
| Pod is `Pending` | "Employee wants to work but there's no desk for them" | Check node labels: `kubectl describe pod <name> -n three-tier` |
| Pod is `CrashLoopBackOff` | "Employee keeps fainting after sitting down" | Check logs: `kubectl logs <pod-name> -n three-tier` |
| Pod is `ImagePullBackOff` | "HR ordered equipment but the delivery failed" | Check image name is correct and you have internet |
| `connection timed out` in network test | "Phone line is dead (network policy blocking)" | If this is EXPECTED, your policies work! If not, check `kubectl get networkpolicy -n three-tier` |
| `admission webhook denied` | "Security guard rejected the entry" | If this is EXPECTED (testing Kyverno), great! If not, check your image tags and security context |
| `0/4 nodes are available` | "No floor has the right department sign" | Re-run: `kubectl label node <node-name> tier=<tier> --overwrite` |
| `cluster-setup.sh: Permission denied` | "The magic button isn't pressable" | Run: `chmod +x cluster-setup.sh` |
| `k3d: command not found` | "You don't have the building toolkit" | Reinstall k3d (see Chapter 2) |

### The Golden Debugging Commands:

```bash
# "What's happening with my employee?" (Pod details + events)
kubectl describe pod <pod-name> -n three-tier

# "What is my employee saying?" (Container logs)
kubectl logs <pod-name> -n three-tier

# "What happened recently?" (Events sorted by time)
kubectl get events -n three-tier --sort-by='.lastTimestamp'

# "Show me everything in my company" (All resources)
kubectl get all -n three-tier

# "Let me go inside and check manually" (Shell into a pod)
kubectl exec -it <pod-name> -n three-tier -- sh

# "NUCLEAR OPTION: Destroy everything and start fresh"
k3d cluster delete three-tier
./cluster-setup.sh
```

---

# 🎯 FINAL SUMMARY

## Your Project in One Picture:

```
                     🏢 YOUR KUBERNETES CLUSTER
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║  🏷️ tier=frontend    🏷️ tier=backend    🏷️ tier=db    ║
    ║  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  ║
    ║  │ 👤 nginx     │  │ 👤 python    │  │ 👤 busybox │  ║
    ║  │ 👤 nginx     │  │ 👤 python    │  │            │  ║
    ║  │ (2 replicas) │  │ (2 replicas) │  │(1 replica) │  ║
    ║  │              │  │              │  │            │  ║
    ║  │ 📞 :80       │──►│ 📞 :8080     │──►│ 📞 :3306   │  ║
    ║  │              │  │              │  │            │  ║
    ║  │ 🛡️ PDB: ≥1   │  │ 🛡️ PDB: ≥1   │  │            │  ║
    ║  └──────────────┘  └──────────────┘  └────────────┘  ║
    ║        │                                   ▲          ║
    ║        └──────────── ❌ BLOCKED ───────────┘          ║
    ║                                                       ║
    ║  🔒 Network Policy: Default deny + explicit allow     ║
    ║  🛂 Kyverno: No privileged, no :latest                ║
    ║  📦 Resources: Requests + Limits on every container   ║
    ╚═══════════════════════════════════════════════════════╝
```

## The 7 Things This Project Proves:

| # | Concept | You Proved It By |
|---|---|---|
| 1 | **Workload Isolation** | Pods are on correct nodes (`kubectl get pods -o wide`) |
| 2 | **High Availability** | 2 replicas per app tier |
| 3 | **Zero-Trust Network** | Frontend→DB is blocked |
| 4 | **Admission Control** | Privileged pods are rejected |
| 5 | **Resilience** | PDB prevents total downtime during drain |
| 6 | **Resource Management** | Every container has requests + limits |
| 7 | **Reproducibility** | One script builds everything from scratch |

**You're now ready to explain this project in any interview. Good luck! 🚀**
