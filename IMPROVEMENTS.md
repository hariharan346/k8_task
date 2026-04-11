# Production-Grade Kubernetes Improvements

## Why Current Approach is "Best Effort"

### The Core Problem

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                 KUBERNETES SCHEDULER TRADE-OFFS                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  preferredDuringSchedulingIgnoredDuringExecution:                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  "Prefer" = Hint to scheduler, NOT a hard requirement             │   │
│  │  - Scheduler scores nodes (higher = better)                      │   │
│  │  - Pods CAN go to ANY node if preferred is unsatisfiable         │   │
│  │  - No guarantee of 70/30 split → More like 70/30/0 if lucky      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  What this means:                                                          │
│  • If Spot nodes exist + have capacity → ~70% on Spot                      │
│  • If Spot nodes FULL → pods spill to Reserved                              │
│  • If Spot nodes EMPTY + Reserved FULL → PODS PENDING                      │
│  • If both FULL → Eviction happens, pods reschedule ANYWHERE               │
│                                                                             │
│  Key insight: "preferred" is a SUGGESTION, not a contract                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Trade-off Matrix

| Constraint Type | Behavior | Guarantee Level | Use Case |
|----------------|----------|-----------------|----------|
| `requiredDuringScheduling` | MUST satisfy or pod waits | **Hard** | Critical workloads |
| `preferredDuringScheduling` | Scores higher = preferred | **Soft** | Cost optimization |
| `topologySpread` | Balances across zones | **Soft** | HA, not placement |
| `podAntiAffinity` | Spreads pods apart | **Soft** | HA, not placement |

**The fundamental Kubernetes trade-off:**
- More cost savings (Spot) = Less predictability = More "best effort"
- More predictability (Reserved) = Less savings = Harder guarantees
- You CANNOT have both maximum savings AND guaranteed placement

---

## Step 1: Stronger Fallback Guarantees

### BEFORE (Current - Soft)

```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 70
        preference:
          matchExpressions:
            - key: pool
              operator: In
              values: [spot]
      - weight: 30
        preference:
          matchExpressions:
            - key: pool
              operator: In
              values: [reserved]
```

**Problem:**
- Pods can go ANYWHERE if both pools are full
- No guaranteed fallback - just "preferred"

### AFTER (Production-Grade)

```yaml
affinity:
  nodeAffinity:
    # PRIMARY: Prefer spot for cost savings (70% bias)
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 70
        preference:
          matchExpressions:
            - key: pool
              operator: In
              values: [spot]
      - weight: 30
        preference:
          matchExpressions:
            - key: pool
              operator: In
              values: [reserved]
    # FALLBACK: Hard requirement if spot unavailable
    # This kicks in ONLY when preferred cannot be satisfied
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: pool
              operator: In
              values: [reserved, spot]
```

**Why this works:**
- First tries to honor soft preferences (70% spot if available)
- If NO spot nodes available → falls back to ANY node with `reserved` or `spot` label
- If NO spot + NO reserved → WAITS (pod pending) instead of going anywhere
- Guarantees: "Cost-optimized IF possible, reserved IF needed, blocked if exhausted"

---

## Step 2: Better PDB for Replica Maintenance

### BEFORE (minAvailable - Current)

```yaml
spec:
  minAvailable: 2
```

**Problem:**
- From 6 replicas: minAvailable: 2 means max 4 can be evicted at once
- But: "How do we know WHEN to fail over to reserved?"
- Answer: We don't explicitly control this

### AFTER (maxUnavailable - Production)

```yaml
spec:
  # STRATEGY: Slow rollout = built-in fallback time
  # At any time, at least 4 pods are AVAILABLE
  maxUnavailable: 2  
  minAvailable: null  # Let Kubernetes handle the rest

# ROLLOUT: Controlled replacement → automatic fallback
strategy:
  type: RollingUpdate  # One at a time or maxUnavailable
  rollingUpdate:
    maxSurge: 1       # Allow 1 extra pod during update
    maxUnavailable: 2 # Keep at least 4 running (from 6)
```

**How this works for Spot drain:**
```
Timeline of spot-node drain:
─────────────────────────────────────────────────────────────
T0: 6 pods running (4 spot, 2 reserved)
    │                                                    
T1: Spot node drains → 4 pods become "Terminating"       
    │                                                    
T2: PDB blocks further evictions (only 2 allowed)        
    │                                                    
T3: Kubernetes RESCHEDULES allowed 2 → Reserved nodes  
    │                                                    
T4: Remaining 2 wait in "Terminating" (blocked by PDB)    
    │                                                    
T5: Spot node gone → NEW spot pods reschedule to reserved  
    │                                                    
    → RESULT: 6/6 maintained, but spread across nodes    
    → KEY insight: PDB rate-limits eviction → buys time for fallback
```

**Why maxUnavailable is better:**
- Controls HOW FAST evictions happen (not IF)
- Rate-limits = guaranteed time for rescheduling
- Creates natural "breathing room" for fallback

---

## Step 3: Improved Topology Spread

### BEFORE (Current)

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
```

**Problem:**
- `ScheduleAnyway` = Don't care if spread is violated
- Pods can stack on one node if cluster is stressed

### AFTER (Production-Grade)

```yaml
topologySpreadConstraints:
  # CONSTRAINT 1: Enforce spread across nodes (hard requirement)
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule  # STRONGER: Block, don't cheat
    labelSelector:
      matchLabels:
        app: frontend
  # CONSTRAINT 2: Enforce spread across zones (if using topology)
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway  # Soft for zone failures
    labelSelector:
      matchLabels:
        app: frontend
```

**Trade-off explanation:**
- `DoNotSchedule` = Pod waits if spread violated (more predictable)
- `ScheduleAnyway` = Place pod anywhere if can't meet spread (more available)
- Interview answer: "We use DoNotSchedule for node-level HA, ScheduleAnyway for zone-level"

---

## Step 4: Complete Production-Grade Frontend Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: three-tier
  labels:
    app: frontend
    tier: frontend
spec:
  replicas: 6
  selector:
    matchLabels:
      app: frontend
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 2
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
    spec:
      affinity:
        # STEP 1: Cost-optimized preference (70% spot)
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 70
              preference:
                matchExpressions:
                  - key: pool
                    operator: In
                    values: [spot]
            - weight: 30
              preference:
                matchExpressions:
                  - key: pool
                    operator: In
                    values: [reserved]
          # STEP 2: Hard fallback when preferred fails
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: pool
                    operator: In
                    values: [reserved, spot]
        # STEP 3: Spread across nodes (HA)
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values: [frontend]
                topologyKey: kubernetes.io/hostname
        # STEP 4: Topology spread (deterministic)
        topologySpreadConstraints:
          - maxSkew: 1
            topologyKey: kubernetes.io/hostname
            whenUnsatisfiable: DoNotSchedule
            labelSelector:
              matchLabels:
                app: frontend
      containers:
        - name: nginx
          image: nginx:1.25.4
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
      tolerations:
        - key: "spot"
          operator: Exists
          effect: NoSchedule
          # Allows running on spot nodes (which have NoSchedule taint)
```

---

## Step 5: Rebalancing Strategy

### Problem with Current Approach
```yaml
# descheduler-values.yaml (current)
RemovePodsViolatingNodeAffinity:
  enabled: true
  # EVICTS pods to force rebalancing
  # BUT: Evicts ALL non-compliant pods at once
```

### Improved Strategy (Production)

```yaml
# Option 1: Selective rebalancing (keep running pods)
deschedulerPolicy:
  strategies:
    RemovePodsViolatingNodeAffinity:
      enabled: true
      params:
        nodeAffinityType:
          - "requiredDuringSchedulingIgnoredDuringExecution"
        # Only evict if on WRONG pool (not just soft violation)
    
    RemovePodsViolatingTopologySpreadConstraint:
      enabled: true
      params:
        includeSoftConstraints: false  # Only hard constraints

# Option 2: Use eviction API (gradual, controlled)
# kubectl --dry-run=client -o jsonpath='{.spec.template}'
# Manual: evict one pod at a time, wait for reschedule

# Option 3: Pod controller rebalancing (best for spot)
# - OnScaleUp: New pods follow affinity (spot)
# - Controller naturally rebalances desired state
# - Descheduler only fixes drift
```

**Key insight:**
- Prefer controller natural rebalancing over forced eviction
- Use descheduler as drift corrector, not primary mechanism
- For spot: New deployments go to spot automatically

---

## Interview Explanation (Simple English)

### For a Co-founder

> "Think of our Kubernetes setup like a hotel with two room types: premium (reserved) and discount (spot).
> 
> Our current approach: We PREFER discount rooms but will take ANY room if none available.
> - Works ~70% of the time, saves money
> - But sometimes guests get upgraded unexpectedly
> 
> Our improved approach: We PREFER discount rooms, but if those are FULL, we WAIT for a premium room rather than giving you any random room.
> - Still saves money 70% of the time
> - When spot rooms are full, guests wait (get best available) rather than being scattered randomly
> - We also limit how fast rooms are cleared (PDB) so there's always time to find a new room
> 
> Trade-off we accept: Sometimes pods wait in pending state instead of immediately running on any node. This gives us more predictability in exchange for slightly less aggressive cost savings.
> 
> This is the same trade-off Airbnb makes: 'Wait for the right room' vs 'Take whatever's available'."

---

## Summary: What Changed and Why

| Aspect | Before | After | Interview Reason |
|--------|--------|-------|------------------|
| Spot affinity | Soft preference | Soft + hard fallback | "Guaranteed when needed" |
| PDB strategy | minAvailable | maxUnavailable | "Rate-limited evictions" |
| Topology | ScheduleAnyway | DoNotSchedule | "Enforced HA" |
| Rebalancing | Forced eviction | Controller-first | "Less disruptive" |
| Fallback behavior | Go anywhere | Wait for capacity | "More predictable" |

---

## Optional: Karpenter High-Level

### How Karpenter Improves This

```yaml
# Karpenter uses "provisioners" instead of affinity
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: spot-provisioner
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot"]
    - key: pool
      operator: In
      values: ["spot"]
  limits:
    resources:
      cpu: 32
      memory: 64Gi
  ttlSecondsAfterEmpty: 60
  weight: 70  # Higher weight = preferred

---
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: reserved-provisioner
spec:
  requirements:
    - key: pool
      operator: In
      values: ["reserved"]
  weight: 30  # Lower weight = fallback
```

**Advantages of Karpenter:**
1. Automatic node provisioning (scales spot capacity automatically)
2. Native spot interruption handling (consolidates on warning)
3. Better bin-packing (more efficient use)
4. Weight-based scheduling at infrastructure level, not pod level

**Disadvantages:**
1. More complex (additional component to manage)
2. AWS-specific features (not all cloud-agnostic)
3. Learning curve for team

---

## Production Checklist

- [ ] Test spot node drain (kubectl cordon + drain)
- [ ] Verify PDB blocks over-eviction
- [ ] Test rebalancing after spot recovery
- [ ] Set up alerts for pending pods
- [ ] Implement capacity monitoring
- [ ] Add Karpenter or cluster autoscaler for capacity management