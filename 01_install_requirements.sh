#!/usr/bin/env bash

# Wrapper script to run the Ansible playbook
# This replaces the original 01_install_requirements.sh

set -ex

# Source the original environment setup
source logging.sh
source common.sh
source sanitychecks.sh
source utils.sh
source validation.sh

# Export environment variables that the playbook expects
export WORKING_DIR=${WORKING_DIR:-$(pwd)}
export METAL3_DEV_ENV_PATH=${METAL3_DEV_ENV_PATH:-"${WORKING_DIR}/metal3-dev-env"}
export ANSIBLE_VERSION=${ANSIBLE_VERSION:-"8.0.0"}
export GO_VERSION=${GO_VERSION:-"1.22.3"}

# Also need the 3.9 version of netaddr for ansible.netcommon
# and lxml for the pyxpath script
sudo python -m pip install netaddr lxml ansible=="${ANSIBLE_VERSION}"

# Run the Ansible playbook
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -i inventory.ini \
  -b -vvv install_requirements.yml

echo "Installation completed successfully!"
