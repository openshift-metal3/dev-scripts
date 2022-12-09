#!/usr/bin/env bash
# shellcheck source=/dev/null
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source "$SCRIPTDIR"/common.sh

for ip in $(cat "${OCP_DIR}"/hostip); 
do 
    echo "Trying to gather agent logs on host ${ip}"
    if ssh -o 'ConnectTimeout=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' core@"${ip}" agent-gather -O >agent-gather-"${ip}".tar.xz; then
    echo "Agent logs saved to agent-gather-"${ip}".tar.xz" >&2
    else
        if [ $? == 127 ]; then
            echo "Skipping gathering agent logs, agent-gather script not present on host ${ip}." >&2
        fi
        rm agent-gather-"${ip}".tar.xz
    fi
done
