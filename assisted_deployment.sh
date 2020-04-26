#!/usr/bin/env bash

source logging.sh
source utils.sh
source common.sh


TEST_INFRA_DIR=$WORKING_DIR/test-infra
export TEST_INFRA_BRANCH=${TEST_INFRA_BRANCH:-master}
export ASSISTED_NETWORK=${ASSISTED_NETWORK:-"test-infra-net"}
export INSTALL=${INSTALL:-"y"}


function install_assisted_env() {
  pushd $WORKING_DIR
  if cd $TEST_INFRA_DIR;then
    git fetch --all && git reset --hard origin/$TEST_INFRA_BRANCH;
  else
    git clone --branch $TEST_INFRA_BRANCH https://github.com/tsorya/test-infra.git;
  fi
  popd
  pushd $TEST_INFRA_DIR
  KUBECONFIG=$PWD/minikube_kubeconfig ./create_full_environment.sh
  popd

  if ! [ "$MANAGE_BR_BRIDGE" == "y" ];then
    swtich_to_internal_dns
  fi

}

function run_flow() {
    pushd $TEST_INFRA_DIR
    source scripts/assisted_deployment.sh
    run $1
    popd
}

#TODO ADD ALL RELEVANT OS ENVS
function run_assisted_flow() {
  run_flow "run_full_flow"
}

function run_assisted_flow_with_install() {
  run_flow "run_full_flow_with_install"
  mkdir -p ocp/${CLUSTER_NAME}/auth
  cp $TEST_INFRA_DIR/build/kubeconfig ocp/${CLUSTER_NAME}/auth/kubeconfig
}


function create_assisted_cluster() {
  if [ "$INSTALL" == "y" ]; then
     run_assisted_flow_with_install
  else
     run_assisted_flow
  fi
  API_VIP=$(network_ip ${ASSISTED_NETWORK:-"test-infra-net"})
  echo "server=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf
  sudo systemctl reload NetworkManager
}

install_assisted_env
create_assisted_cluster
