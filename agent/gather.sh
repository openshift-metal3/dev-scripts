#!/usr/bin/env bash
# shellcheck source=/dev/null
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source "$SCRIPTDIR"/common.sh

for host in $(cat "${OCP_DIR}"/hostname); 
do 
    echo "Trying to gather agent logs on host ${host}"
    if ssh -o 'ConnectTimeout=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' core@"${host}" agent-gather -O >agent-gather-"${host}".tar.xz; then
        echo "Agent logs saved to agent-gather-"${host}".tar.xz" >&2
    else
        if [ $? == 127 ]; then
            echo "Skipping gathering agent logs, agent-gather script not present on host ${host}." >&2
        fi
        rm agent-gather-"${host}".tar.xz
    fi
done
