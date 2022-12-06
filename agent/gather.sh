#!/usr/bin/env bash
# shellcheck source=/dev/null
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source "$SCRIPTDIR"/agent/04_agent_configure.sh

ip=$(<"${OCP_DIR}"/node0-ip)

ssh -o 'ConnectTimeout=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' core@"${ip}" if ! command -v /usr/local/bin/agent-gather '>&' /dev/null ';' then echo "Skipping gathering agent logs, agent-gather script not present." else sudo /usr/local/bin/agent-gather -o ';' fi >agent-gather.tar.xz
