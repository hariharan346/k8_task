#!/bin/bash
set -euo pipefail

#===============================================================
# Trivy Image Vulnerability Scanner
# Scans all images used in the 3-tier application.
# Requires: trivy (https://aquasecurity.github.io/trivy/)
#===============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

#---------------------------------------------------------------
# 1. Check if Trivy is installed
#---------------------------------------------------------------
if ! command -v trivy &>/dev/null; then
  warn "Trivy is not installed. Attempting to install..."

  # Try common install methods
  if command -v brew &>/dev/null; then
    brew install trivy
  elif command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq wget apt-transport-https gnupg lsb-release
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
    echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
    sudo apt-get update -qq && sudo apt-get install -y -qq trivy
  else
    fail "Cannot auto-install Trivy. Please install manually:"
    echo "  https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
    exit 1
  fi
fi

ok "Trivy found: $(trivy --version 2>/dev/null | head -1)"

#---------------------------------------------------------------
# 2. Define images to scan
#---------------------------------------------------------------
IMAGES=(
  "nginx:1.25.4"
  "python:3.12-slim"
  "busybox:1.36"
)

REPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/reports"
mkdir -p "$REPORT_DIR"

#---------------------------------------------------------------
# 3. Scan each image
#---------------------------------------------------------------
OVERALL_EXIT=0

for IMAGE in "${IMAGES[@]}"; do
  echo ""
  echo "============================================================"
  info "Scanning image: $IMAGE"
  echo "============================================================"

  SAFE_NAME=$(echo "$IMAGE" | tr ':/' '_')

  # Run Trivy scan — table output to terminal, JSON to file
  trivy image \
    --severity HIGH,CRITICAL \
    --format table \
    "$IMAGE" | tee "$REPORT_DIR/${SAFE_NAME}_scan.txt"

  # Also save a JSON report for programmatic use
  trivy image \
    --severity HIGH,CRITICAL \
    --format json \
    --output "$REPORT_DIR/${SAFE_NAME}_scan.json" \
    "$IMAGE" 2>/dev/null

  if [ ${PIPESTATUS[0]:-0} -ne 0 ]; then
    warn "$IMAGE has HIGH/CRITICAL vulnerabilities (see report above)"
    OVERALL_EXIT=1
  else
    ok "$IMAGE scan complete."
  fi
done

#---------------------------------------------------------------
# 4. Summary
#---------------------------------------------------------------
echo ""
echo "============================================================"
info "Scan Reports saved to: $REPORT_DIR/"
ls -la "$REPORT_DIR/"
echo "============================================================"

if [ "$OVERALL_EXIT" -ne 0 ]; then
  warn "Some images have HIGH/CRITICAL vulnerabilities. Review reports above."
else
  ok "All images passed vulnerability scan."
fi

exit 0
