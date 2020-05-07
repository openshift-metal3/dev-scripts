#!/usr/bin/env bash
set -o pipefail

source logging.sh
source utils.sh
source common.sh
source assisted_deployment_utils.sh



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


install_assisted_env
create_assisted_cluster
