# My 3-Tier Kubernetes Resilience Project

So, I built this project to show how a real-world Kubernetes setup handles workload distribution between different types of nodes—specifically "Spot" and "Reserved" pools. The goal was to keep 70% of the traffic on cheaper Spot nodes while keeping 30% on reliable Reserved nodes, all while making sure the system doesn't break if one pool disappears.

### 🏗️ What this project does
It's a classic 3-tier app (Frontend, Backend, and a Database). 
- **Frontend/Backend:** They live across both Spot and Reserved nodes.
- **Database:** It's pinned to the Reserved node because you don't want your data disappearing on a Spot termination.
- **70/30 Split:** I used "Preferred" affinity. This means the scheduler tries its best to hit the 70/30 target but won't stop the pods from running if it can't (graceful degradation).
- **Security:** I used Kyverno for policy enforcement and Network Policies for zero trust.

### 🛠️ How I set it up
I didn't want to do everything manually every time, so I wrote a bootstrap script.
1. **Cluster Creation:** I used `k3d` to spin up a local cluster with 1 master and 3 worker nodes.
2. **Labeling:** I specifically labeled one node as `pool=reserved` and the others as `pool=spot`. I also added "tier" labels so pods know where they are allowed to go.
3. **App Deployment:** I deployed the tiers with PodDisruptionBudgets (PDBs) so we don't accidentally kill too many pods at once during maintenance.
4. **Hardening:** I installed Kyverno to block things like using the `:latest` image tag or running as a privileged container. I also implemented a **Restricted Security Profile** across all tiers:
    - **`runAsNonRoot: true`**: Pods are forbidden from running as root.
    - **`readOnlyRootFilesystem: true`**: The application disk is immutable to prevent malware persistence.
    - **`allowPrivilegeEscalation: false`**: Processes cannot gain more rights than they started with.
    - **Network Policies**: I added policies to block all traffic except what's actually needed (e.g., Frontend talking to Backend).

### 📄 Important configs / scripts I created
- **`cluster-setup.sh`**: This is the main one. It sets up the cluster, labels everything, and waits for every single pod to be "Green" before finishing. I spent a lot of time on the "wait" functions to make it reliable.
- **`tests/chaos-demo.sh`**: This is an interactive script that walks through 14 different failure scenarios (like deleting nodes or scaling up to 20 pods) to show exactly how the 70/30 split holds up.
- **`descheduler-values.yaml`**: This config tells the cluster how to move pods back to their "preferred" nodes once a failed node comes back online.

### 🚀 How to run and test it
To get everything running from scratch:
```bash
./cluster-setup.sh
```
Once it's finished, you can run the chaos demo to see it in action:
```bash
./tests/chaos-demo.sh
```
Or if you want to test things manually, you can scale the frontend and watch the distribution:
```bash
kubectl scale deployment frontend -n three-tier --replicas=10
kubectl get pods -n three-tier -o wide
```

### 🔍 What to observe
- When you scale up, you'll see more pods landing on the agent-1/agent-2 nodes (Spot) than on agent-0 (Reserved).
- If you "drain" a Spot node, the pods will jump over to the remaining nodes without dropping traffic.
- If you delete the Spot pool labels, everything will safely move to the Reserved node instead of staying in "Pending" state.

### ⚠️ Issues I faced and fixes
- **Timing:** Kyverno takes a few seconds to set up its webhooks. Initially, my script would fail because it tried to deploy the app before the security policy was actually enforcing. I fixed this by adding a "wait for webhook" loop.
- **Cross-platform:** I'm on Windows, but the scripts are Bash. I had to handle `.exe` calls for `kubectl` and `k3d` inside the scripts so they work regardless of whether you're in WSL, Git Bash, or Linux.
- **Rebalancing:** Kubernetes doesn't move pods just because a node came back online. I had to add a `Descheduler` to actually rebalance the cluster after a recovery.

### 🧹 Cleanup
If you're done and want to wipe everything:
```bash
k3d cluster delete three-tier
```
I simplified it so there's no leftover trash—just one command and your resources are back.
