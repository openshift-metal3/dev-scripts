#!/bin/bash
#
# Auto-approve pending CSRs for a specified duration
#
# Usage: ./auto_approve_csrs.sh [duration_minutes]
#
# Default duration is 30 minutes
#

set -euo pipefail

DURATION_MINUTES=${1:-30}
DURATION_SECONDS=$((DURATION_MINUTES * 60))

echo "Auto-approving CSRs for ${DURATION_MINUTES} minutes..."
echo "Press Ctrl+C to stop"

timeout=$DURATION_SECONDS
elapsed=0

while (( elapsed < timeout )); do
    # Get pending CSRs
    pending_csrs=$(oc get csr 2>/dev/null | grep Pending | awk '{print $1}' || true)
    
    if [ -n "$pending_csrs" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found pending CSRs:"
        echo "$pending_csrs"
        echo "$pending_csrs" | xargs -r oc adm certificate approve
        echo "Approved!"
    fi
    
    elapsed=$((elapsed + 10))
    sleep 10
done

echo "Auto-approval period complete"

