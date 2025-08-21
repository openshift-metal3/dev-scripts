#!/usr/bin/env bash

# Example script showing how to run the Ansible playbook with environment variables
# This demonstrates the same environment setup as the original bash script

export WORKING_DIR="/home/metalhead/metal3"
export METAL3_DEV_ENV_PATH="${WORKING_DIR}/metal3-dev-env"
export ANSIBLE_VERSION="8.0.0"
export GO_VERSION="1.22.3"
export OPENSHIFT_CLIENT_TOOLS_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz"

# Optional environment variables
# export KNI_INSTALL_FROM_GIT="true"
# export PERSISTENT_IMAGEREG="true"
# export NODES_PLATFORM="baremetal"

# Run the playbook
ansible-playbook -i inventory.ini install_requirements.yml -v

echo "Installation completed!"
