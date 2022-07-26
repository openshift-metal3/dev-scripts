#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/agent/common.sh

early_deploy_validation

function create_image() {
    local asset_dir="${1:-${OCP_DIR}}"
    local openshift_install="$(realpath "${OCP_DIR}/openshift-install")"
    "${openshift_install}" --dir="${asset_dir}" --log-level=debug agent create image
}

function attach_agent_iso() {

    # This is required to allow qemu opening the disk image
    if [ "${OPENSHIFT_CI}" == true ]; then
      setfacl -m u:qemu:rx /root
    fi

    for (( n=0; n<${2}; n++ ))
    do
        name=${CLUSTER_NAME}_${1}_${n}
        sudo virt-xml ${name} --add-device --disk "${OCP_DIR}/agent.iso",device=cdrom,target.dev=sdc
        sudo virt-xml ${name} --edit target=sda --disk="boot_order=1"
        sudo virt-xml ${name} --edit target=sdc --disk="boot_order=2" --start
    done
}

function get_node0_ip() {
  node0_name=$(printf ${MASTER_HOSTNAME_FORMAT} 0)
  node0_ip=$(sudo virsh net-dumpxml ostestbm | xmllint --xpath "string(//dns[*]/host/hostname[. = '${node0_name}']/../@ip)" -)
  echo "${node0_ip}"
}

function force_mirror_disconnect() {

  # Set a bogus entry in /etc/hosts on all masters to force the local mirror to be used
  node0_ip=$(get_node0_ip)
  ssh_opts=(-o 'StrictHostKeyChecking=no' -q core@${node0_ip})

  for (( n=0; n<${NUM_MASTERS}; n++ ))
  do
     node_name=$(printf ${MASTER_HOSTNAME_FORMAT} $n)
     node_ip=$(sudo virsh net-dumpxml ostestbm | xmllint --xpath "string(//dns[*]/host/hostname[. = '${node_name}']/../@ip)" -)
     ssh_opts=(-o 'StrictHostKeyChecking=no' -q core@${node_ip})

     until ssh "${ssh_opts[@]}" "[[ -f /etc/hosts ]]"
     do
       echo "Waiting for $node_name to set remote host disconnect "
       sleep 30s;
     done

     # Set a bogus entry in /etc/hosts to break remote access
     ssh "${ssh_opts[@]}" "echo '125.12.15.15 quay.io' | sudo tee -a /etc/hosts "
     ssh "${ssh_opts[@]}" "echo '125.12.15.16 registry.ci.openshift.org' | sudo tee -a /etc/hosts "
  done

}

function enable_assisted_service_ui() {
  node0_ip=$(get_node0_ip)
  ssh_opts=(-o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -q core@${node0_ip})

  until ssh "${ssh_opts[@]}" "[[ -f /run/assisted-service-pod.pod-id ]]"
  do
    echo "Waiting for node0"
    sleep 5s;
  done

  ssh "${ssh_opts[@]}" "sudo /usr/bin/podman run -d --name=assisted-ui --pod-id-file=/run/assisted-service-pod.pod-id quay.io/edge-infrastructure/assisted-installer-ui:latest"
}

function wait_for_cluster_ready() {

  node0_ip=$(get_node0_ip)
  ssh_opts=(-o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -q core@${node0_ip})

  until ssh "${ssh_opts[@]}" "[[ -f /var/lib/kubelet/kubeconfig ]]" 
  do 
    echo "Waiting for bootstrap... "
    sleep 1m; 
  done

  sleep 5m

  echo "Waiting for cluster ready... "
  if oc wait --for=condition=Ready nodes --all --timeout=60m --kubeconfig=${OCP_DIR}/auth/kubeconfig; then
    echo "Cluster is ready!"
  else
    exit 1
  fi
}

create_image

attach_agent_iso master $NUM_MASTERS
attach_agent_iso worker $NUM_WORKERS

if [ ! -z "${MIRROR_IMAGES}" ]; then
  force_mirror_disconnect
fi

if [ ! -z "${AGENT_ENABLE_GUI:-}" ]; then
  enable_assisted_service_ui
fi


wait_for_cluster_ready
# Temporary fix for the CI. To be removed once we'll 
# be able to generate the cluster credentials
if [ "${OPENSHIFT_CI}" == true ]; then
  touch ${OCP_DIR}/auth/kubeadmin-password
fi

