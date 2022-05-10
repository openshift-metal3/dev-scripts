#!/usr/bin/env bash
set -ex

# If you have run devscripts on the machine this will already be done but we
# need ansible before devscripts is going to install it.
sudo dnf -y install python39
sudo pip3 install ansible netaddr

# Installs the local devscripts.agente2e collection
AGENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ansible-galaxy collection install --force $AGENT_SCRIPT_DIR

# needed for assisted-service to run nmstatectl
# This is temporary and will go away when https://github.com/nmstate/nmstate is used
sudo yum install -y nmstate
