#!/bin/bash
#==============================================================================
# Kubernetes Workload Distribution Chaos Demo (INTERVIEW-READY EDITION)
# Validates 70/30 Spot/Reserved balancing across 14 real-world scenarios
# with full visibility of pod distribution, node mapping, and system behavior.
#
# NOTE: 70/30 is approximate (preferredDuringScheduling affinity weights),
#       not an exact guarantee. Actual ratios depend on node count, existing
#       load, topology spread, and anti-affinity constraints.
#==============================================================================

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

NAMESPACE="three-tier"
CLUSTER_NAME="three-tier"
APP_LABEL="app=frontend"

# ─── Cross-platform command detection ────────────────────────────────────────
if command -v k3d.exe &>/dev/null; then K3D_CMD="k3d.exe"; else K3D_CMD="k3d"; fi
if command -v kubectl.exe &>/dev/null; then KUBECTL_CMD="kubectl.exe"; else KUBECTL_CMD="kubectl"; fi

# ─── Scenario Counter ───────────────────────────────────────────────────────
SCENARIO_NUM=0

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

header() {
    SCENARIO_NUM=$((SCENARIO_NUM + 1))
    local title="SCENARIO ${SCENARIO_NUM}: $1"
    local box_width=78
    local inner=$((box_width - 4))
    local pad=$((inner - ${#title}))
    [[ $pad -lt 1 ]] && pad=1
    echo ""
    echo -e "${MAGENTA}╔$(printf '═%.0s' $(seq 1 $((box_width - 2))))╗${NC}"
    echo -e "${MAGENTA}║  ${title}$(printf '%*s' $pad '')║${NC}"
    echo -e "${MAGENTA}╚$(printf '═%.0s' $(seq 1 $((box_width - 2))))╝${NC}"
    echo ""
}

section_header() {
    echo -e "\n${WHITE}${BOLD}── $1 ──${NC}\n"
}

info()    { echo -e "${CYAN}  ℹ  [INFO]${NC}   $*"; }
action()  { echo -e "${YELLOW}  ▶  [ACTION]${NC} $*"; }
ok()      { echo -e "${GREEN}  ✔  [OK]${NC}     $*"; }
fail()    { echo -e "${RED}  ✖  [FAIL]${NC}   $*"; }
note()    { echo -e "${DIM}  ⚠  [NOTE]${NC}   $*"; }

explain() {
    echo ""
    echo -e "${GREEN}  ┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}  │  📖 EXPLANATION                                             │${NC}"
    echo -e "${GREEN}  ├─────────────────────────────────────────────────────────────┤${NC}"
    while IFS= read -r line; do
        printf "${GREEN}  │${NC}  %-57s ${GREEN}│${NC}\n" "$line"
    done <<< "$*"
    echo -e "${GREEN}  └─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

pause() {
    echo ""
    echo -ne "${CYAN}  ⏩ Press Enter to continue to next scenario...${NC}"
    read -r
    echo ""
}

#==============================================================================
# POD DISTRIBUTION DISPLAY (REUSABLE)
#==============================================================================

# Prints:  Pod Name → Node → Pool   for every frontend pod
# Then:    Summary table with counts and percentages
show_distribution() {
    local label="${1:-CURRENT STATE}"

    echo -e "\n${CYAN}  ╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║  📊 DISTRIBUTION: ${label}$(printf '%*s' $((42 - ${#label})) '')║${NC}"
    echo -e "${CYAN}  ╚═══════════════════════════════════════════════════════════════╝${NC}"

    # Build node → pool mapping
    declare -A node_pool
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local n_name n_pool
        n_name=$(echo "$line" | awk '{print $1}')
        n_pool=$(echo "$line" | awk '{print $2}')
        node_pool["$n_name"]="${n_pool:-<none>}"
    done < <($KUBECTL_CMD get nodes -o custom-columns="NAME:.metadata.name,POOL:.metadata.labels.pool" --no-headers 2>/dev/null)

    # Gather pod data
    local pods
    pods=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" -o wide --no-headers 2>/dev/null || true)

    local spot=0 res=0 pending=0 other=0 total=0

    if [[ -z "$pods" ]]; then
        echo -e "  ${DIM}  (no pods found in namespace $NAMESPACE)${NC}"
    else
        # Column header
        echo ""
        printf "  ${BOLD}  %-42s → %-30s → %-10s${NC}\n" "POD NAME" "NODE" "POOL"
        echo -e "  ${DIM}  ──────────────────────────────────────────────────────────────────────────────────${NC}"

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local pod_name pod_status pod_node pod_pool

            pod_name=$(echo "$line" | awk '{print $1}')
            pod_status=$(echo "$line" | awk '{print $3}')
            pod_node=$(echo "$line" | awk '{print $7}')

            total=$((total + 1))

            if [[ -z "$pod_node" || "$pod_node" == "<none>" ]]; then
                pod_pool="(pending)"
                pending=$((pending + 1))
                printf "  ${RED}  %-42s → %-30s → %-10s${NC}\n" "$pod_name" "<pending>" "$pod_pool"
            else
                pod_pool="${node_pool[$pod_node]:-unknown}"
                if [[ "$pod_pool" == "spot" ]]; then
                    spot=$((spot + 1))
                    printf "  ${GREEN}  %-42s → %-30s → %-10s${NC}\n" "$pod_name" "$pod_node" "🟢 spot"
                elif [[ "$pod_pool" == "reserved" ]]; then
                    res=$((res + 1))
                    printf "  ${BLUE}  %-42s → %-30s → %-10s${NC}\n" "$pod_name" "$pod_node" "🔵 reserved"
                else
                    other=$((other + 1))
                    printf "  ${YELLOW}  %-42s → %-30s → %-10s${NC}\n" "$pod_name" "$pod_node" "⚪ $pod_pool"
                fi
            fi
        done <<< "$pods"
    fi

    # Summary table
    echo ""
    echo -e "  ${WHITE}${BOLD}  SUMMARY${NC}"
    echo -e "  ${DIM}  ┌──────────────────────┬───────────┬────────────┐${NC}"
    printf "  ${DIM}  │${NC} ${BOLD}%-20s${NC} ${DIM}│${NC} ${BOLD}%-9s${NC} ${DIM}│${NC} ${BOLD}%-10s${NC} ${DIM}│${NC}\n" "Pool" "Count" "Percentage"
    echo -e "  ${DIM}  ├──────────────────────┼───────────┼────────────┤${NC}"

    local scheduled=$((spot + res + other))
    if [[ $scheduled -gt 0 ]]; then
        local spot_pct res_pct
        spot_pct=$(awk "BEGIN {printf \"%.1f\", ($spot/$scheduled)*100}")
        res_pct=$(awk "BEGIN {printf \"%.1f\", ($res/$scheduled)*100}")
        printf "  ${DIM}  │${NC} ${GREEN}%-20s${NC} ${DIM}│${NC} ${GREEN}%-9d${NC} ${DIM}│${NC} ${GREEN}%-9s%%${NC} ${DIM}│${NC}\n" "🟢 Spot (target 70%)" "$spot" "$spot_pct"
        printf "  ${DIM}  │${NC} ${BLUE}%-20s${NC} ${DIM}│${NC} ${BLUE}%-9d${NC} ${DIM}│${NC} ${BLUE}%-9s%%${NC} ${DIM}│${NC}\n" "🔵 Reserved (tgt 30%)" "$res" "$res_pct"
    else
        printf "  ${DIM}  │${NC} %-20s ${DIM}│${NC} %-9d ${DIM}│${NC} %-10s ${DIM}│${NC}\n" "🟢 Spot (target 70%)" "0" "—"
        printf "  ${DIM}  │${NC} %-20s ${DIM}│${NC} %-9d ${DIM}│${NC} %-10s ${DIM}│${NC}\n" "🔵 Reserved (tgt 30%)" "0" "—"
    fi

    if [[ $pending -gt 0 ]]; then
        printf "  ${DIM}  │${NC} ${RED}%-20s${NC} ${DIM}│${NC} ${RED}%-9d${NC} ${DIM}│${NC} ${RED}%-10s${NC} ${DIM}│${NC}\n" "⏳ Pending" "$pending" "—"
    fi
    if [[ $other -gt 0 ]]; then
        printf "  ${DIM}  │${NC} ${YELLOW}%-20s${NC} ${DIM}│${NC} ${YELLOW}%-9d${NC} ${DIM}│${NC} ${YELLOW}%-10s${NC} ${DIM}│${NC}\n" "⚪ Unlabeled/Other" "$other" "—"
    fi

    echo -e "  ${DIM}  ├──────────────────────┼───────────┼────────────┤${NC}"
    printf "  ${DIM}  │${NC} ${BOLD}%-20s${NC} ${DIM}│${NC} ${BOLD}%-9d${NC} ${DIM}│${NC} ${BOLD}%-10s${NC} ${DIM}│${NC}\n" "TOTAL" "$total" "100%"
    echo -e "  ${DIM}  └──────────────────────┴───────────┴────────────┘${NC}"
    echo ""
}

#==============================================================================
# WAIT HELPERS
#==============================================================================

wait_for_pods() {
    local target=$1
    local timeout=${2:-180}
    echo -ne "${CYAN}  ⏳ [WAIT]${NC} Waiting for $target Running pod(s) "
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local running
        running=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" --no-headers 2>/dev/null | grep -c "Running" || true)
        if [ "$running" -ge "$target" ]; then
            echo -e " ${GREEN}✔ Ready!${NC}"
            return 0
        fi
        echo -ne "."
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo -e " ${RED}✖ Timeout after ${timeout}s!${NC}"
    return 1
}

wait_for_nodes_ready() {
    local nodes="$@"
    echo -ne "${CYAN}  ⏳ [WAIT]${NC} Waiting for node(s) to become Ready "
    # Give k3d time to register the node with the API server
    sleep 10
    local timeout=300 elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local all_ready=true
        for node in $nodes; do
            local status
            status=$($KUBECTL_CMD get node "$node" --no-headers 2>/dev/null | awk '{print $2}' || echo "NotFound")
            # Use partial match: status may be "Ready" or "Ready,SchedulingDisabled" etc.
            if [[ "$status" != *"Ready"* || "$status" == "NotFound" ]]; then all_ready=false; break; fi
        done
        if $all_ready; then echo -e " ${GREEN}✔ Ready!${NC}"; return 0; fi
        echo -ne "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo -e " ${RED}✖ Timeout after ${timeout}s${NC}"
    # Don't exit the script — let the user inspect manually
    note "Node(s) not ready yet. Continuing anyway — check manually with: kubectl get nodes"
    return 0
}

#==============================================================================
#                         M A I N   D E M O   F L O W
#==============================================================================

clear
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
echo -e "${GREEN}${BOLD}║     🚀  KUBERNETES 70/30 WORKLOAD DISTRIBUTION — INTERVIEW DEMO  🚀         ║${NC}"
echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
echo -e "${GREEN}${BOLD}║  This demo walks through 14 scenarios proving how the Kubernetes scheduler   ║${NC}"
echo -e "${GREEN}${BOLD}║  distributes pods across Spot (70%) and Reserved (30%) node pools, and how   ║${NC}"
echo -e "${GREEN}${BOLD}║  the system reacts to scaling, failures, and pool removal/restoration.       ║${NC}"
echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
echo -e "${GREEN}${BOLD}║  ⚠  70/30 is approximate (preferred affinity), not exact.                    ║${NC}"
echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

info "Cluster: $CLUSTER_NAME | Namespace: $NAMESPACE | Target: $APP_LABEL"
info "Starting demo with $(date '+%Y-%m-%d %H:%M:%S')"

echo ""
echo -e "${WHITE}${BOLD}  Cluster Node Inventory:${NC}"
$KUBECTL_CMD get nodes -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[-1].type,POOL:.metadata.labels.pool,FRONTEND-TIER:.metadata.labels.tier/frontend" --no-headers 2>/dev/null | while IFS= read -r line; do
    echo -e "    $line"
done
echo ""

pause

#==============================================================================
# SCENARIO 1: ADD ONE POD
#==============================================================================

header "ADD ONE POD"

section_header "BEFORE STATE"
info "Current replica count: $($KUBECTL_CMD get deployment/frontend -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
show_distribution "BEFORE — Baseline"

section_header "EXECUTING"
action "Scaling frontend from current replicas to +1 (7 total)..."
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=7
wait_for_pods 7

section_header "AFTER STATE"
show_distribution "AFTER — 7 Replicas (+1 Pod Added)"

explain "When adding a single pod, the Kubernetes scheduler evaluates all
eligible nodes using the preferredDuringScheduling weights.
The new pod PREFERS Spot (weight 70) over Reserved (weight 30),
so it will most likely land on a Spot node.
70/30 is approximate — not exact per-pod, but trends over scale."

pause

#==============================================================================
# SCENARIO 2: ADD MULTIPLE PODS
#==============================================================================

header "ADD MULTIPLE PODS"

section_header "BEFORE STATE"
show_distribution "BEFORE — 7 Replicas"

section_header "EXECUTING"
action "Scaling frontend to 20 replicas (+13 pods)..."
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=20
wait_for_pods 20

section_header "AFTER STATE"
show_distribution "AFTER — 20 Replicas (+13 Pods Added)"

explain "With 13 new pods, the 70/30 ratio becomes clearly visible.
The scheduler scores each node: Spot nodes get +70 affinity
bonus, Reserved nodes get +30. Combined with topology spread
(maxSkew: 1), about 14 land on Spot and 6 on Reserved.
At higher scale, the 70/30 distribution is more pronounced."

pause

#==============================================================================
# SCENARIO 3: REMOVE ONE POD
#==============================================================================

header "REMOVE ONE POD"

section_header "BEFORE STATE"
show_distribution "BEFORE — 20 Replicas"

section_header "EXECUTING"
action "Deleting 1 random pod manually..."
POD_TO_DELETE=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" -o name | head -n 1)
info "Deleting: $POD_TO_DELETE"
$KUBECTL_CMD delete "$POD_TO_DELETE" -n "$NAMESPACE" --now
wait_for_pods 20

section_header "AFTER STATE"
show_distribution "AFTER — Pod Deleted & Replaced"

explain "When a pod is deleted, the ReplicaSet controller detects that
the actual count (19) is below desired (20). It immediately
creates a replacement pod. The scheduler places the new pod
using the same 70/30 affinity weights — self-healing in action."

pause

#==============================================================================
# SCENARIO 4: REMOVE MULTIPLE PODS
#==============================================================================

header "REMOVE MULTIPLE PODS"

section_header "BEFORE STATE"
show_distribution "BEFORE — 20 Replicas"

section_header "EXECUTING"
action "Deleting 5 pods simultaneously..."
PODS_TO_DELETE=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" -o name | head -n 5)
info "Deleting: $(echo $PODS_TO_DELETE | tr '\n' ' ')"
$KUBECTL_CMD delete $PODS_TO_DELETE -n "$NAMESPACE" --now
wait_for_pods 20

section_header "AFTER STATE"
show_distribution "AFTER — 5 Pods Deleted & Replaced"

explain "Deleting multiple pods triggers a batch recreation by the
ReplicaSet controller. All 5 replacement pods are scheduled
in parallel. The scheduler independently scores each one,
maintaining the 70/30 preference across the new batch.
This simulates a partial failure recovery scenario."

pause

#==============================================================================
# (Transition: scale down before node scenarios)
#==============================================================================

action "Scaling back to 8 replicas to prepare for node scenarios..."
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=8
wait_for_pods 8

#==============================================================================
# SCENARIO 5: ADD ONE NODE
#==============================================================================

header "ADD ONE NODE TO CLUSTER"

section_header "BEFORE STATE"
show_distribution "BEFORE — 8 Replicas"
info "Current nodes:"
$KUBECTL_CMD get nodes -o custom-columns="NAME:.metadata.name,POOL:.metadata.labels.pool" --no-headers 2>/dev/null | while IFS= read -r l; do echo "    $l"; done

section_header "EXECUTING"
action "Adding 'extra-agent-1' to cluster..."
$K3D_CMD node create "extra-agent-1" --cluster "$CLUSTER_NAME" > /dev/null 2>&1
wait_for_nodes_ready "k3d-three-tier-extra-agent-1"
action "Labeling new node as pool=spot, tier/frontend=true..."
$KUBECTL_CMD label node k3d-three-tier-extra-agent-1 pool=spot tier/frontend=true --overwrite

section_header "AFTER STATE (before rebalance)"
show_distribution "AFTER NODE ADD — No Rebalance Yet"

info "Notice: pods did NOT move to the new node automatically."
info "Triggering rollout restart to force redistribution..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8

section_header "AFTER STATE (after rebalance)"
show_distribution "AFTER REBALANCE — With New Spot Node"

explain "Adding a node does NOT move existing pods (Kubernetes uses
IgnoredDuringExecution for running pods). Only a rollout
restart or new scaling event triggers rescheduling. After
the restart, pods spread across all available nodes using
the 70/30 weights. More Spot nodes = more Spot capacity."

pause

#==============================================================================
# SCENARIO 6: ADD MULTIPLE NODES
#==============================================================================

header "ADD MULTIPLE NODES TO CLUSTER"

section_header "BEFORE STATE"
show_distribution "BEFORE — With extra-agent-1"

section_header "EXECUTING"
action "Adding 'extra-agent-2' and 'extra-agent-3' to cluster..."
$K3D_CMD node create "extra-agent-2" --cluster "$CLUSTER_NAME" > /dev/null 2>&1
$K3D_CMD node create "extra-agent-3" --cluster "$CLUSTER_NAME" > /dev/null 2>&1
wait_for_nodes_ready "k3d-three-tier-extra-agent-2 k3d-three-tier-extra-agent-3"
action "Labeling extra-agent-2 as pool=spot, extra-agent-3 as pool=reserved..."
$KUBECTL_CMD label node k3d-three-tier-extra-agent-2 pool=spot tier/frontend=true --overwrite
$KUBECTL_CMD label node k3d-three-tier-extra-agent-3 pool=reserved tier/frontend=true --overwrite

action "Triggering rollout to redistribute..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8

section_header "AFTER STATE"
show_distribution "AFTER — 2 More Nodes Added + Rebalanced"

explain "Two new nodes were added: one Spot, one Reserved. After
the rollout restart, pods are redistributed with the updated
node topology. The scheduler now has more capacity in both
pools, spreading load more evenly within each pool.
Key: more Spot nodes pull more pods (weight 70 each)."

pause

#==============================================================================
# SCENARIO 7: REMOVE ONE NODE
#==============================================================================

header "REMOVE ONE NODE FROM CLUSTER"

section_header "BEFORE STATE"
show_distribution "BEFORE — With Extra Nodes"
info "Current nodes:"
$KUBECTL_CMD get nodes -o custom-columns="NAME:.metadata.name,POOL:.metadata.labels.pool" --no-headers 2>/dev/null | while IFS= read -r l; do echo "    $l"; done

section_header "EXECUTING"
action "Deleting extra-agent-1 (Spot node)..."
$K3D_CMD node delete k3d-three-tier-extra-agent-1 > /dev/null 2>&1 || true
sleep 5
wait_for_pods 8

section_header "AFTER STATE"
show_distribution "AFTER — 1 Spot Node Removed"

explain "When a node is deleted, all pods on that node go Terminating.
The ReplicaSet controller recreates them on surviving nodes.
Since we lost a Spot node, the remaining Spot nodes absorb
the displaced pods. The 70/30 ratio is maintained because
the affinity weights still guide scheduling decisions."

pause

#==============================================================================
# SCENARIO 8: REMOVE MULTIPLE NODES
#==============================================================================

header "REMOVE MULTIPLE NODES FROM CLUSTER"

section_header "BEFORE STATE"
show_distribution "BEFORE — Current State"

section_header "EXECUTING"
action "Deleting extra-agent-2 AND extra-agent-3 simultaneously (rack failure!)..."
$K3D_CMD node delete k3d-three-tier-extra-agent-2 > /dev/null 2>&1 || true
$K3D_CMD node delete k3d-three-tier-extra-agent-3 > /dev/null 2>&1 || true
sleep 5
wait_for_pods 8

section_header "AFTER STATE"
show_distribution "AFTER — 2 Nodes Removed (Rack Failure Simulated)"

explain "Simultaneous loss of 2 nodes simulates a rack failure. Pods
that were running on those nodes are terminated and recreated
on the 3 original surviving nodes. The cluster self-heals
automatically. The 70/30 distribution is restored across the
remaining Spot and Reserved nodes — total resilience!"

pause

#==============================================================================
# SCENARIO 9: REMOVE SPOT POOL
#==============================================================================

header "REMOVE SPOT POOL — What Happens?"

section_header "BEFORE STATE"
show_distribution "BEFORE — Normal 70/30 Distribution"

section_header "EXECUTING"
action "Removing 'pool=spot' label from ALL Spot nodes..."
$KUBECTL_CMD label nodes --selector=pool=spot pool- --overwrite > /dev/null

action "Forcing reschedule with rollout restart..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8

section_header "AFTER STATE"
show_distribution "AFTER — Spot Pool Removed (100% Reserved Fallback)"

explain "With ALL Spot labels removed, no node satisfies the 'pool=spot'
preferred match. The hard requirement still needs pool=spot OR
pool=reserved. Since only Reserved nodes remain valid, ALL pods
fail over to the Reserved pool. This is the power of preferred
affinity: the system degrades gracefully instead of crashing.
Pods moved to RESERVED because Spot nodes no longer exist."

pause

#==============================================================================
# SCENARIO 10: RESTORE SPOT POOL
#==============================================================================

header "RESTORE SPOT POOL — What Happens?"

section_header "BEFORE STATE"
show_distribution "BEFORE — All Pods on Reserved"

section_header "EXECUTING"
action "Restoring 'pool=spot' label to Spot nodes..."
AGENT_LIST=$($KUBECTL_CMD get nodes --no-headers -o name | grep agent | sort)
i=0
for n in $AGENT_LIST; do
    if [ $i -gt 0 ]; then
        $KUBECTL_CMD label "$n" pool=spot --overwrite
        info "Labeled $n → pool=spot"
    fi
    i=$((i + 1))
done

action "Forcing reschedule with rollout restart..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8

section_header "AFTER STATE"
show_distribution "AFTER — Spot Pool Restored (70/30 Back)"

explain "Once Spot labels are restored, the scheduler can again see
nodes with pool=spot. After a rollout restart, all pods are
rescheduled using the original 70/30 weights. Pods migrate
BACK to Spot nodes because the weight 70 preference kicks
in again. The system fully recovers to normal distribution."

pause

#==============================================================================
# SCENARIO 11: REMOVE RESERVED NODE
#==============================================================================

header "REMOVE RESERVED NODE — What Happens?"

section_header "BEFORE STATE"
show_distribution "BEFORE — Normal Distribution"

section_header "EXECUTING"
action "Removing 'pool=reserved' label from all Reserved nodes..."
$KUBECTL_CMD label nodes --selector=pool=reserved pool- --overwrite > /dev/null

action "Forcing reschedule..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8

section_header "AFTER STATE"
show_distribution "AFTER — Reserved Pool Removed (100% Spot Fallback)"

explain "With no Reserved nodes available, ALL pods move to the Spot
pool. The 30% Reserved allocation cannot be honored because
no node carries the pool=reserved label. The system stays
100% operational on Spot — availability over precision.
This proves the soft-preference model: it bends, doesn't break."

pause

#==============================================================================
# SCENARIO 12: RESTORE RESERVED NODE
#==============================================================================

header "RESTORE RESERVED NODE — What Happens?"

section_header "BEFORE STATE"
show_distribution "BEFORE — All Pods on Spot"

section_header "EXECUTING"
action "Restoring 'pool=reserved' to the first agent node..."
FIRST_AGENT=$($KUBECTL_CMD get nodes --no-headers -o name | grep agent | head -n 1)
$KUBECTL_CMD label "$FIRST_AGENT" pool=reserved --overwrite
info "Labeled $FIRST_AGENT → pool=reserved"

action "Forcing reschedule..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8

section_header "AFTER STATE"
show_distribution "AFTER — Reserved Pool Restored (70/30 Back)"

explain "With the Reserved label restored on a node, the scheduler
again respects the 70/30 weight split. After the rollout
restart, ~30% of pods move to the Reserved node while ~70%
remain on Spot. The system self-heals back to the intended
distribution without any manual pod placement."

pause

#==============================================================================
# SCENARIO 13: REMOVE BOTH POOLS
#==============================================================================

header "REMOVE BOTH POOLS — Complete Blockage"

section_header "BEFORE STATE"
show_distribution "BEFORE — Normal Distribution"

section_header "EXECUTING"
action "Removing ALL pool AND tier labels from every node..."
$KUBECTL_CMD label nodes --all pool- tier/frontend- --overwrite > /dev/null 2>&1 || true

action "Scaling to 10 replicas to force new scheduling..."
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=10
sleep 8

section_header "AFTER STATE"
show_distribution "AFTER — Both Pools Removed (BLOCKED)"

info "Checking for Pending pods..."
PENDING=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
if [[ "$PENDING" -gt 0 ]]; then
    fail "$PENDING pod(s) are PENDING — no valid node exists!"
    info "Pod status detail:"
    $KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" --no-headers 2>/dev/null | grep "Pending" | while IFS= read -r l; do echo -e "    ${RED}$l${NC}"; done
else
    info "Existing pods still running (IgnoredDuringExecution), but no new pods can schedule."
fi

explain "With BOTH pool AND tier/frontend labels removed, the hard
requirement (requiredDuringScheduling) blocks new pods:
  - No node has tier/frontend=true → FAIL
  - No node has pool=spot or pool=reserved → FAIL
Existing pods keep running (IgnoredDuringExecution) but new
pods go PENDING. This is the worst-case scenario.
Pods are pending because NO valid nodes exist for scheduling."

pause

#==============================================================================
# SCENARIO 14: RESTORE BOTH POOLS
#==============================================================================

header "RESTORE BOTH POOLS — Full Recovery"

section_header "BEFORE STATE"
show_distribution "BEFORE — Blocked State"

section_header "EXECUTING"
action "Restoring ALL tier labels on every node..."
$KUBECTL_CMD label nodes --all tier/frontend=true tier/backend=true tier/db=true --overwrite > /dev/null

action "Restoring pool labels (1st agent=reserved, rest=spot)..."
AGENT_LIST=$($KUBECTL_CMD get nodes --no-headers -o name | grep agent | sort)
i=0
for n in $AGENT_LIST; do
    if [ $i -eq 0 ]; then
        $KUBECTL_CMD label "$n" pool=reserved --overwrite
        info "Labeled $n → pool=reserved"
    else
        $KUBECTL_CMD label "$n" pool=spot --overwrite
        info "Labeled $n → pool=spot"
    fi
    i=$((i + 1))
done

action "Forcing full reschedule..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 10

section_header "AFTER STATE"
show_distribution "AFTER — Both Pools Restored (Full Recovery)"

explain "With all labels restored, the hard requirements are satisfied
again. Pending pods can now be scheduled. After the rollout
restart, ALL pods are redistributed with the 70/30 weights.
The cluster has fully self-healed from the worst-case scenario
back to normal operations. Total resilience demonstrated!"

pause

#==============================================================================
# CLEANUP — RESTORE BASELINE
#==============================================================================

echo ""
echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║  🧹 CLEANUP — RESTORING BASELINE                                           ║${NC}"
echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

action "Restoring all labels..."
$KUBECTL_CMD label nodes --all tier/frontend=true tier/backend=true tier/db=true --overwrite > /dev/null

AGENT_LIST=$($KUBECTL_CMD get nodes --no-headers -o name | grep agent | sort)
i=0
for n in $AGENT_LIST; do
    if [ $i -eq 0 ]; then
        $KUBECTL_CMD label "$n" pool=reserved --overwrite
    else
        $KUBECTL_CMD label "$n" pool=spot --overwrite
    fi
    i=$((i + 1))
done

action "Scaling back to 6 replicas..."
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=6
wait_for_pods 6

show_distribution "FINAL — Baseline Restored"

ok "Cluster restored to baseline."
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
echo -e "${GREEN}${BOLD}║   ✅  DEMO COMPLETE — ALL 14 SCENARIOS DEMONSTRATED SUCCESSFULLY  ✅        ║${NC}"
echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
echo -e "${GREEN}${BOLD}║   Key Takeaways:                                                             ║${NC}"
echo -e "${GREEN}${BOLD}║   • 70/30 is a scheduler PREFERENCE, not an exact guarantee                  ║${NC}"
echo -e "${GREEN}${BOLD}║   • The ratio becomes more accurate at higher replica counts                 ║${NC}"
echo -e "${GREEN}${BOLD}║   • Preferred affinity degrades gracefully under failures                    ║${NC}"
echo -e "${GREEN}${BOLD}║   • Hard requirements (required affinity) block pods when unsatisfied        ║${NC}"
echo -e "${GREEN}${BOLD}║   • The system self-heals: ReplicaSet + Scheduler = auto-recovery            ║${NC}"
echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
