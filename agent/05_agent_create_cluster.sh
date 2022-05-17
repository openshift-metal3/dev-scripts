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
  pushd ${OCP_DIR}
  ./openshift-install --dir "${OCP_DIR}" --log-level=debug agent create image
  popd  
}

function attach_agent_iso() {
    for (( n=0; n<${2}; n++ ))
    do
        name=${CLUSTER_NAME}_${1}_${n}
        sudo virt-xml ${name} --add-device --disk "${OCP_DIR}/output/agent.iso",device=cdrom,target.dev=sdc
        sudo virt-xml ${name} --edit target=sda --disk="boot_order=1"
        sudo virt-xml ${name} --edit target=sdc --disk="boot_order=2" --start
    done
}

function wait_for_cluster_ready() {

  node0_name=$(printf ${MASTER_HOSTNAME_FORMAT} 0)
  node0_ip=$(sudo virsh net-dumpxml ostestbm | xmllint --xpath "string(//dns[*]/host/hostname[. = '${node0_name}']/../@ip)" -)
  ssh_opts=(-o 'StrictHostKeyChecking=no' -q core@${node0_ip})

  until ssh "${ssh_opts[@]}" "[[ -f /var/lib/kubelet/kubeconfig ]]" 
  do 
    echo "Waiting for bootstrap... "
    sleep 1m; 
  done

  sleep 5m

  echo "Waiting for cluster ready... "
  if ssh "${ssh_opts[@]}" "sudo  oc wait --for=condition=Ready nodes --all --timeout=60m --kubeconfig=/var/lib/kubelet/kubeconfig"; then
    echo "Cluster is ready!"
  else
    exit 1
  fi
}

create_image

attach_agent_iso master $NUM_MASTERS
attach_agent_iso worker $NUM_WORKERS

wait_for_cluster_ready
