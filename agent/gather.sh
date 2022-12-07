#!/usr/bin/env bash
# shellcheck source=/dev/null
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source "$SCRIPTDIR"/common.sh

ip=$(<"${OCP_DIR}"/node0-ip)

if ssh -o 'ConnectTimeout=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' core@"${ip}" agent-gather -O >agent-gather.tar.xz; then
    echo "Agent logs saved to agent-gather.tar.xz" >&2
else
    if [ $? == 127 ]; then
        echo "Skipping gathering agent logs, agent-gather script not present." >&2
    fi
    rm agent-gather.tar.xz
fi
