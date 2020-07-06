#!/usr/bin/env bash
set -o pipefail
source common.sh
source logging.sh

TEST_INFRA_DIR=$WORKING_DIR/assisted-test-infra
export TEST_INFRA_BRANCH=${TEST_INFRA_BRANCH:-master}
export ASSISTED_NETWORK=${ASSISTED_NETWORK:-"test-infra-net"}
export INSTALL=${INSTALL:-"y"}
export WAIT_FOR_CLUSTER=${WAIT_FOR_CLUSTER:-"y"}
export INSTALLER_IMAGE=${INSTALLER_IMAGE:-}
export SERVICE=${SERVICE:-}


function destroy_assisted_nodes(){
  echo "Destroying assisted_deployment vms"
  run_assisted_command "destroy_nodes"
}

function run_assisted_command () {
  pushd $TEST_INFRA_DIR
  source scripts/assisted_deployment.sh
  run_skipper_make_command "$1"
  popd
}

function deploy_assisted_nodes() {
  if [ "$INSTALL" == "y" ]; then
    run_assisted_flow_with_install
  else
    run_assisted_flow
  fi
}

#TODO ADD ALL RELEVANT OS ENVS
function run_assisted_flow() {
  run_assisted_command "run_full_flow KUBECONFIG=$TEST_INFRA_DIR/minikube_kubeconfig"
}

function run_assisted_flow_with_install() {
  run_assisted_command "run_full_flow_with_install KUBECONFIG=$TEST_INFRA_DIR/minikube_kubeconfig"
  mkdir -p ocp/${CLUSTER_NAME}/auth
  cp $TEST_INFRA_DIR/build/kubeconfig ocp/${CLUSTER_NAME}/auth/kubeconfig
}

function run_assisted_action() {
    run_assisted_command "${ACTION} KUBECONFIG=$TEST_INFRA_DIR/minikube_kubeconfig"
}

function set_assisted_dns() {
  API_VIP=$(network_ip ${ASSISTED_NETWORK:-"test-infra-net"})
  FILENAME=/etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf
  echo "" > $FILENAME
  echo "server=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee $FILENAME
  sudo systemctl reload NetworkManager
}

function create_assisted_cluster() {
  deploy_assisted_nodes
  set_assisted_dns
  if [ "$INSTALL" == "y" ] && [ "$WAIT_FOR_CLUSTER" == "y" ]; then
    wait_for_assited_cluster
  fi
}

function wait_for_assited_cluster() {
  pushd $TEST_INFRA_DIR
  source scripts/assisted_deployment.sh
  wait_for_cluster "$1"
  popd
}

"$@"
