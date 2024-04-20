#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh
source $SCRIPTDIR/ocp_install_env.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/agent/common.sh

early_deploy_validation

function build_node_joiner() {
  # Build installer
  pushd .
  cd $OPENSHIFT_INSTALL_PATH
  TAGS="${OPENSHIFT_INSTALLER_BUILD_TAGS:-libvirt baremetal}" DEFAULT_ARCH=$(get_arch) hack/build-node-joiner.sh
  popd
}

function approve_csrs() {
  while true; do
    pending_csrs=$(oc get csr | grep Pending)
    if [[ ${pending_csrs} != "" ]]; then
      echo "Approving CSRs: $pending_csrs"
      echo $pending_csrs | cut -d ' ' -f 1 | xargs oc adm certificate approve
    fi
    sleep 10
  done
}

if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
  # Extract node-joiner from the release image
  baremetal_installer_image=$(oc adm release info --image-for=baremetal-installer --registry-config=$PULL_SECRET_FILE)
  container_id=$(podman create --authfile $PULL_SECRET_FILE ${baremetal_installer_image} ls)
  podman start $container_id
  podman export $container_id > baremetal-installer.tar
  tar xf baremetal-installer.tar usr/bin/node-joiner
  cp usr/bin/node-joiner $OCP_DIR/node-joiner
  rm -rf usr baremetal-installer.tar
  podman rm $container_id
else
  # Build the node-joiner from source
  build_node_joiner
  cp "$OPENSHIFT_INSTALL_PATH/bin/node-joiner" "$OCP_DIR"
fi

get_static_ips_and_macs

node_joiner="$(realpath "${OCP_DIR}/node-joiner")"

extra_node_to_join=0

$node_joiner add-nodes --dir $OCP_DIR/add-node --kubeconfig $OCP_DIR/auth/kubeconfig

sudo virt-xml ${CLUSTER_NAME}_extraworker_${extra_node_to_join} --add-device --disk "${OCP_DIR}/add-node/node.x86_64.iso,device=cdrom,target.dev=sdc"
sudo virt-xml ${CLUSTER_NAME}_extraworker_${extra_node_to_join} --edit target=sda --disk="boot_order=1"
sudo virt-xml ${CLUSTER_NAME}_extraworker_${extra_node_to_join} --edit target=sdc --disk="boot_order=2" --start

set +ex
approve_csrs &
set -ex

$node_joiner monitor-add-nodes ${AGENT_EXTRA_WORKERS_IPS[${extra_node_to_join}]} --kubeconfig $OCP_DIR/auth/kubeconfig

oc get nodes extraworker-${extra_node_to_join} | grep Ready