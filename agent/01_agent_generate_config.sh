#!/usr/bin/env bash
set -ex

AGENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z ${OPENSHIFT_CI+x} ]; then
  ansible-playbook $AGENT_SCRIPT_DIR/playbooks/generate_config.yml
else
  ansible-playbook $AGENT_SCRIPT_DIR/playbooks/generate_config.yml \
  -e "ci_token=${CI_TOKEN}" \
  -e "working_dir=${WORKING_DIR}" \
  -e "openshift_release_stream=${OPENSHIFT_RELEASE_STREAM}" \
  -e "openshift_release_type=${OPENSHIFT_RELEASE_TYPE}" \
  -e "openshift_version=${OPENSHIFT_VERSION}" \
  -e "cluster_name=${CLUSTER_NAME}" \
  -e "base_domain=${BASE_DOMAIN}" \
  -e "cluster_topology=${CLUSTER_TOPOLOGY}" \
  -e "resource_profile=${RESOURCE_PROFILE}" \
  -e "extra_workers_profile=${EXTRA_WORKERS_PROFILE}" \
  -e "ip_stack=${IP_STACK}" \
  -e "host_ip_stack=${HOST_IP_STACK}" \
  -e "provisioning_network_profile=${PROVISIONING_NETOWORK_PROFILE}" \
  -e "agent_static_ip_node0_only=${AGENT_STATIC_IP_NODE0_ONLY}"
fi