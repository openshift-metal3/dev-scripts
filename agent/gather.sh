#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/agent/04_agent_configure.sh

get_static_ips_and_macs

if [[ "$IP_STACK" = "v4" ]]; then
    ip=${AGENT_NODES_IPS[0]}
  else
    ip=${AGENT_NODES_IPSV6[0]}
  fi

ssh -o 'ConnectTimeout=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' core@${ip} << EOF
# check is agent-gather command is present
if ! command -v /usr/local/bin/agent-gather &> /dev/null
then
    echo "/usr/local/bin/agent-gather could not be found."
    exit
fi

sudo /usr/local/bin/agent-gather -O | tar -xJvf -
EOF