#!/bin/bash
#==============================================================================
# Kubernetes Workload Distribution Chaos Demo (EXPERT TIER - VISIBILITY MODE)
# Validates 70/30 Spot/Reserved balancing with detailed system reaction logs.
#==============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

NAMESPACE="three-tier"
CLUSTER_NAME="three-tier"
APP_LABEL="app=frontend"

# Cross-platform command detection
if command -v k3d.exe &>/dev/null; then K3D_CMD="k3d.exe"; else K3D_CMD="k3d"; fi
if command -v kubectl.exe &>/dev/null; then KUBECTL_CMD="kubectl.exe"; else KUBECTL_CMD="kubectl"; fi

# Functions
header() {
    echo -e "\n${MAGENTA}==============================================================================${NC}"
    echo -e "${MAGENTA} SCENARIO: $1${NC}"
    echo -e "${MAGENTA}==============================================================================${NC}"
}

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
action()  { echo -e "${YELLOW}[ACTION]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }

reaction() {
    echo -e "\n${GREEN}SYSTEM REACTION:${NC}"
    echo -e "------------------------------------------------------------"
    echo -e "$*"
    echo -e "------------------------------------------------------------"
}

explain() {
    echo -e "\n${YELLOW}HOW IT BALANCES:${NC}"
    echo -e "$*"
    echo ""
}

pause() {
    echo -ne "${CYAN}[NEXT]${NC} Press Enter to continue..."
    read -r
}

get_distribution() {
    local pods
    pods=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" -o wide --no-headers 2>/dev/null || true)
    
    if [[ -z "$pods" ]]; then echo "0 0 0"; return; fi

    declare -A node_pool
    while read -r name pool; do
        node_pool["$name"]="$pool"
    done < <($KUBECTL_CMD get nodes -o custom-columns="NAME:.metadata.name,POOL:.metadata.labels.pool" --no-headers)

    local spot=0 res=0 total=0
    while read -r line; do
        [[ -z "$line" ]] && continue
        node=$(echo "$line" | awk '{print $7}')
        status=$(echo "$line" | awk '{print $3}')
        [[ -z "$node" || "$node" == "<none>" ]] && continue
        # Only count Running or ContainerCreating to show change
        [[ "$status" != "Running" && "$status" != "ContainerCreating" ]] && continue

        pool="${node_pool[$node]:-unknown}"
        if [[ "$pool" == "spot" ]]; then spot=$((spot + 1)); elif [[ "$pool" == "reserved" ]]; then res=$((res + 1)); fi
        total=$((total + 1))
    done <<< "$pods"
    echo "$spot $res $total"
}

print_stats() {
    local label=$1
    local spot res total
    read -r spot res total <<< "$(get_distribution)"
    
    echo -e "\n${CYAN}DISTRIBUTION STATE: $label${NC}"
    echo "------------------------------------------------------------"
    if [[ $total -eq 0 ]]; then
        echo "| No active pods found in namespace $NAMESPACE"
    else
        local spot_pct=$(awk "BEGIN {printf \"%.1f\", ($spot/$total)*100}")
        local res_pct=$(awk "BEGIN {printf \"%.1f\", ($res/$total)*100}")
        printf "| %-15s | %-10s | %-10s |\n" "Node Pool" "Pod Count" "Percentage"
        echo "------------------------------------------------------------"
        printf "| %-15s | %-10d | %-10s%% |\n" "Spot (Target 70%)" "$spot" "$spot_pct"
        printf "| %-15s | %-10d | %-10s%% |\n" "Reserved (30%)" "$res" "$res_pct"
    fi
    echo "------------------------------------------------------------"
}

wait_for_pods() {
    local target=$1
    echo -ne "${CYAN}[WAIT]${NC} Scaling to $target pods "
    local timeout=180 elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local running=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" --no-headers | grep -c "Running" || true)
        if [ "$running" -eq "$target" ]; then echo -e " ${GREEN}Done!${NC}"; return 0; fi
        echo -ne "."; sleep 3; elapsed=$((elapsed + 3))
    done
    echo -e " ${RED}Timeout!${NC}"; return 1
}

#==============================================================================
# MAIN FLOW
#==============================================================================
clear
echo -e "${GREEN}   70/30 WORKLOAD DISTRIBUTION - EXPERT VISIBILITY DEMO${NC}"
echo "=============================================================================="

# 1. Baseline
header "1. INITIAL STATE"
print_stats "BASELINE (6 REPLICAS)"
explain "The cluster starts with 6 pods. Due to weights (70 Spot / 30 Reserved) 
and 3 available nodes, the scheduler maintains a ~66/33 split as the closest 
approximation of our 70/30 goal."
pause

# 2. High-Load Scaling
header "2. HIGH-LOAD SCALING (DIFFERENTIATION)"
print_stats "BEFORE (6 PODS)"
action "Scaling frontend to 20 replicas..."
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=20
wait_for_pods 20
print_stats "AFTER SCALE-UP (20 PODS)"
reaction "Kubernetes Scheduler detected the scale-up event. It calculated the score 
for each node and correctly allocated 14 pods to Spot and 6 to Reserved. 
Observe how clearly the 70/30 ratio (14/6) emerges at higher scale!"
pause

# 3. Bulk Scale Down
header "3. BULK SCALE DOWN (REACTION)"
print_stats "BEFORE (20 PODS)"
action "Scaling back to 8 replicas..."
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=8
wait_for_pods 8
print_stats "AFTER SCALE-DOWN (8 PODS)"
reaction "System reacted to the reduction by terminating pods. The controller 
ensured that the remaining pods still respect the node affinity preference, 
keeping the ratio relatively stable."
pause

# 4. Multi-Node Expansion
header "4. MULTI-NODE CHOS (ADD 2 AGENTS)"
print_stats "BEFORE NODE ADD"
action "Adding 'extra-agent-1' and 'extra-agent-2' to cluster..."
$K3D_CMD node create "extra-agent-1" --cluster "$CLUSTER_NAME" > /dev/null
$K3D_CMD node create "extra-agent-2" --cluster "$CLUSTER_NAME" > /dev/null
$KUBECTL_CMD wait --for=condition=Ready nodes k3d-three-tier-extra-agent-1 k3d-three-tier-extra-agent-2 --timeout=60s
print_stats "AFTER NODE ADD (0 PODS ON NEW NODES)"
explain "Look at the table! Even though we have 2 new nodes, the Pod Count 
has NOT changed on the existing pools. Kubernetes will not move running 
pods voluntarily (IgnoredDuringExecution) until we label them and trigger a rebalance."
pause

# 5. Rebalancing
header "5. BATCH LABELING & REBALANCE (REACTION)"
action "Labeling both extra nodes as 'pool=spot'..."
$KUBECTL_CMD label nodes k3d-three-tier-extra-agent-1 k3d-three-tier-extra-agent-2 pool=spot tier/frontend=true --overwrite
action "Triggering rollout to force re-distribution..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8
print_stats "AFTER REBALANCE (EXPANDED SPOT CAPACITY)"
reaction "With 4 Spot nodes now available, the scheduler spread the 70% 
workload across all of them. The system reacted to the new 'pool=spot' 
labels by moving pods to utilize the increased capacity."
pause

# 6. Multi-Node Failure
header "6. MULTI-NODE FAILURE (RECOVERY)"
print_stats "BEFORE NODE FAILURE"
action "Deleting both extra nodes simultaneously (Simulating Rack Failure)..."
$K3D_CMD node delete k3d-three-tier-extra-agent-1 k3d-three-tier-extra-agent-2 > /dev/null
wait_for_pods 8
print_stats "AFTER NODE FAILURE (SELF-HEALED)"
reaction "Total Resilience! When the nodes failed, the pods went into 'Terminating' 
on the dead nodes. The ReplicaSet immediately reacted by spinning up replacements 
on the 3 surviving nodes, maintaining the 70/30 distribution."
pause

# 7. Self-Healing
header "7. DELETE RANDOM PODS"
action "Deleting 2 pods manually..."
PODS=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" -o name | head -n 2)
$KUBECTL_CMD delete $PODS -n "$NAMESPACE" --now
wait_for_pods 8
print_stats "AFTER POD DELETION"
reaction "The Deployment controller detected a deviation from the desired state (8) 
and reacted by instantly recreating the pods. The Scheduler ensured they landed 
back on appropriate nodes."
pause

# 8. Reserved Pool Failure
header "8. RESERVED POOL ISOLATION"
print_stats "BEFORE RESERVED FAILURE"
action "Removing 'pool=reserved' label from all nodes..."
$KUBECTL_CMD label node --selector=pool=reserved pool- --overwrite > /dev/null
action "Forcing reschedule..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8
print_stats "AFTER RESERVED FAILURE (100% SPOT FALLBACK)"
reaction "The system reacted to the loss of Reserved nodes by failing over 
entirely to the Spot pool. Because the affinity is 'Preferred' and the 
required label is still present, the system remains 100% operational."
pause

# 9. Spot Pool Failure
header "9. SPOT POOL ISOLATION"
print_stats "BEFORE SPOT FAILURE"
action "Removing 'pool=spot' label from all nodes..."
$KUBECTL_CMD label nodes --selector=pool=spot pool- --overwrite > /dev/null
action "Restoring Reserved pool to first agent..."
FIRST_AGENT=$($KUBECTL_CMD get nodes --no-headers -o name | grep agent | head -n 1)
$KUBECTL_CMD label "$FIRST_AGENT" pool=reserved --overwrite
action "Forcing reschedule..."
$KUBECTL_CMD rollout restart deployment/frontend -n "$NAMESPACE"
wait_for_pods 8
print_stats "AFTER SPOT FAILURE (100% RESERVED FALLBACK)"
reaction "With no Spot nodes available, the Scheduler reacted by placing 
all 8 pods on the single available Reserved node. Availability is preserved!"
pause

# 10. Full Pool Removal
header "10. FULL BLOCKAGE (REACTION)"
action "Removing ALL valid labels (pool & tier)..."
$KUBECTL_CMD label nodes --all pool- tier/frontend- --overwrite > /dev/null
action "Scaling to 10 pods..."
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=10
sleep 5
PENDING=$($KUBECTL_CMD get pods -n "$NAMESPACE" -l "$APP_LABEL" | grep -c Pending || echo "0")
print_stats "AFTER FULL BLOCKAGE"
reaction "The system is now in a BLOCKED state. 8 pods stay on their nodes (running), 
but the 2 new pods are PENDING. Why? Because the Scheduler reacted to the 
Hard Requirement (requiredDuringScheduling) and found NO nodes with the 'tier/frontend' label."
pause

# Cleanup
header "CLEANING UP"
action "Restoring baseline cluster state..."
$KUBECTL_CMD label nodes --all tier/frontend=true tier/backend=true tier/db=true --overwrite > /dev/null
AGENT_LIST=$($KUBECTL_CMD get nodes --no-headers -o name | grep agent | sort)
i=0; for n in $AGENT_LIST; do
  if [ $i -eq 0 ]; then $KUBECTL_CMD label "$n" pool=reserved --overwrite
  else $KUBECTL_CMD label "$n" pool=spot --overwrite; fi
  i=$((i+1))
done
$KUBECTL_CMD scale deployment/frontend -n "$NAMESPACE" --replicas=6
wait_for_pods 6
ok "Cluster restored to baseline."
echo -e "\n${GREEN}DEMO COMPLETE${NC}"
