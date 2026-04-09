# Architecture & Concepts Deep Dive

To confidently pass a DevSecOps/Cloud Engineering interview, you must understand *why* the underlying YAML works the way it does, not just how to run the scripts. 

The architecture we have built is a **Dynamic 3-Tier Web Stack Simulation** designed to handle unpredictable cost-saving hardware mechanisms (Spot instances) while maintaining enterprise-level uptime.


---
## 📁 File-by-File Breakdown

### 1. `cluster-setup.sh`
This is your foundational provisioning script. In a real-world scenario, this script takes the place of tools like Terraform or AWS eksctl. It instructs the Docker engine to provision the underlying hardware boundaries we need. 

**Key Code Snippet & Logic:**
```bash
kubectl label node "${AGENT_NODES[0]}" pool=reserved
kubectl label node "${AGENT_NODES[1]}" pool=spot
```
We assign arbitrary metadata tags to these nodes. Kubernetes schedules based heavily on labels. By explicitly declaring what is "reserved" vs "spot", we create logical boundaries.

### 2. `frontend/deployment.yaml` (The Brain of the Operation)
This is where 90% of the interview magic happens. Let's break down the concepts inside it:

#### Concept A: Replicas & Spread
We instructed the deployment to run `replicas: 6`. If all 6 pods run on the exact same node, a single hardware failure takes the entire service offline.
To solve this, we used:
```yaml
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: pool
          whenUnsatisfiable: ScheduleAnyway
```
**Deep Dive:** 
A Topology Spread Constraint forces the scheduler to distribute pods across failure domains (like availability zones, or in our case, `pools`). 
- `maxSkew: 1` tells Kubernetes "try to ensure the difference in pod counts between our Spot pool and our Reserved pool never exceeds exactly 1 pod".
- `whenUnsatisfiable: ScheduleAnyway` is critical here. It turns the constraint into a soft "best-effort". If one pool goes down completely, we *want* the pods to schedule anyway onto the surviving node, ignoring the constraint temporarily to save the service!

#### Concept B: Node Affinity Weighting
```yaml
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 70  -> spot
            - weight: 30  -> reserved
```
**Deep Dive:**
This satisfies the "30/70" requirement. Instead of hardcoding "Put 4 pods here and 2 pods here", we gave Kubernetes a mathematical scoring index. Kubernetes scores every node. It looks at the spot nodes and adds 70 points. It looks at the reserved node and adds 30 points. It then places the pod on the node with the highest score, gracefully resulting in an approximate percentage-based spread.

### 3. `pdb/frontend-pdb.yaml` (Pod Disruption Budget)
```yaml
spec:
  minAvailable: 2
```
**Deep Dive:**
A PDB protects you from voluntary disruptions (like when an auto-scaler decides to downscale a node, or an admin runs `kubectl drain`). Without a PDB, `kubectl drain` could instantly terminate all 6 of your frontend pods at the exact same millisecond. Your PDB is a contract with Kubernetes: "No matter what operations you run against the nodes, ensure at least 2 of these pods respond to traffic at all times."

### 4. `descheduler-values.yaml` (Automated Rebalancer)
**Deep Dive:**
The Kubernetes scheduler is a one-time event. It only scores nodes and places pods at the exact millisecond a pod is created. Once a pod is running, it stays there forever. 
If an entire spot-pool dies, all pods migrate to the reserved pool. When the spot-pool comes back online, the nodes are completely empty, but your reserved pool is still doing 100% of the work.

The **Descheduler** is an operator that runs as a CRON job. It scans the cluster for scenarios that violate your preferred rules. When it sees those frontend pods crammed onto the reserved node, it gracefully kicks them out (evicts them). Because the pods belong to a ReplicaSet, they are instantly recreated, and the default scheduler re-scores the clusters, realizes the spot capacity is back, and moves them.

### 5. Policies & Security `network-policy.yaml / kyverno-policies.yaml`
**Deep Dive:**
- **Zero-Trust Networking:** The `network-policy.yaml` blocks all traffic across the cluster by default, explicitly carving out hole-punches so only the frontend can tall to the backend, and the backend to the DB.
- **Admission Controllers (Kyverno):** Kubernetes natively allows any user to create a pod running as `<root>`. Kyverno actively hooks into the Kubernetes API request pathway to inspect and block security violations (like `latest` tags) before they are ever allowed to spin up.

---

## 🎯 Interview Follow-Up Question Sandbox

**Q: "If you used Karpenter, how would this differ from what we did natively?"**
*Answer:* "What we did manually with labels and scaling is what Karpenter does autonomously. Karpenter observes the raw `Pending` pods, calculates their resource requirements, and bypasses the native scheduler to rapidly spin up exact-fit Spot instances from AWS directly. If those nodes are reclaimed, Karpenter replaces them on-the-fly without the need for manual node prep or complex descheduler cron hacks."
