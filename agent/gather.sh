#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/agent/04_agent_configure.sh

ip=$(head -n 1 ${OCP_DIR}/node0-ip)

ssh -o 'ConnectTimeout=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' core@${ip} << EOF
# check is agent-gather command is present
if ! command -v /usr/local/bin/agent-gather &> /dev/null
then
    echo "Skipping gathering agent logs, agent-gather script not present."
    exit 0
fi

sudo /usr/local/bin/agent-gather
EOF
