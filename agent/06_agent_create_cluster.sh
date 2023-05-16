#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/ocp_install_env.sh
source $SCRIPTDIR/agent/common.sh

early_deploy_validation

function create_pxe_files() {
    local asset_dir=${1}
    local openshift_install=${2}
    "${openshift_install}" --dir="${asset_dir}" --log-level=debug agent create pxe-files
}

function create_image() {
    local asset_dir=${1}
    local openshift_install=${2}
    "${openshift_install}" --dir="${asset_dir}" --log-level=debug agent create image
}

function attach_agent_iso() {

    # This is required to allow qemu opening the disk image
    if [ "${OPENSHIFT_CI}" == true ]; then
      setfacl -m u:qemu:rx /root
    fi

    local agent_iso="${OCP_DIR}/agent.$(uname -p).iso"
    if [ ! -f "${agent_iso}" -a -f "${OCP_DIR}/agent.iso" ]; then
        agent_iso="${OCP_DIR}/agent.iso"
    fi

    for (( n=0; n<${2}; n++ ))
    do
        name=${CLUSTER_NAME}_${1}_${n}
        sudo virt-xml ${name} --add-device --disk "${agent_iso}",device=cdrom,target.dev=sdc
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

function disable_automated_installation() {
  local agent_iso_abs_path="$(realpath "${OCP_DIR}/agent.$(uname -p).iso")"
  local ign_temp_path="$(mktemp --directory)"
  _tmpfiles="$_tmpfiles $ign_temp_path"
  echo "Extracting ISO ignition..."
  podman run --privileged --rm -v /run/udev:/run/udev -v "${agent_iso_abs_path}:/data/agent.iso" -w /data  quay.io/coreos/coreos-installer:release iso ignition show agent.iso > "${ign_temp_path}/iso.ign"

  echo "disabling automated installation systemd services..."
  jq --compact-output --argjson filterlist '["apply-host-config.service", "create-cluster-and-infraenv.service", "install-status.service", "set-hostname.service", "start-cluster-installation.service"]' \
    'walk( . as $i | if type == "object" and has("enabled") and any($filterlist[]; . == $i.name) then .enabled = false else . end)' < "${ign_temp_path}/iso.ign" > "${ign_temp_path}/disabled_automation.ign"

  echo "Embedding merged ignition..."
  podman run --privileged --rm -v /run/udev:/run/udev -v "${agent_iso_abs_path}:/data/agent.iso" -v "${ign_temp_path}/disabled_automation.ign:/data/disabled_automation.ign" -w /data  quay.io/coreos/coreos-installer:release iso ignition embed -f -i disabled_automation.ign agent.iso
}

function enable_assisted_service_ui() {
  if [[ "${IP_STACK}" = "v6" ]]; then
       echo "In a disconnected environment the assisted-installer GUI cannot be enabled"
       return
  fi
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
  local openshift_install="$(realpath "${OCP_DIR}/openshift-install")"
  if ! "${openshift_install}" --dir="${OCP_DIR}" --log-level=debug agent wait-for bootstrap-complete; then
      exit 1
  fi

  echo "Waiting for cluster ready... "
  "${openshift_install}" --dir="${OCP_DIR}" --log-level=debug agent wait-for install-complete 2>&1 | grep --line-buffered -v 'password'
  if [ ${PIPESTATUS[0]} != 0 ]; then
      exit 1
  fi
  echo "Cluster is ready!"
}

function mce_prepare_postinstallation_manifests() {
  local mceManifests=$1

  # Copy all the manifests required after the installation completed
  cp ${SCRIPTDIR}/agent/mce/agent_mce_1*.yaml ${mceManifests}

  # Render the cluster image set template
  local clusterImageSetTemplate=${mceManifests}/agent_mce_1_04_clusterimageset.yaml
  local version="$(openshift_version ${OCP_DIR})"
  local releaseImage=$(getReleaseImage)

  sed -i "s/<version>/${version}/g" ${clusterImageSetTemplate}
  sed -i "s/<releaseImage>/${releaseImage//\//\\/}/g" ${clusterImageSetTemplate}
}

function mce_apply_postinstallation_manifests() {
  local mceManifests=$1

  wait_for_crd "localvolumes.local.storage.openshift.io"
  apply_manifest "$mceManifests/agent_mce_1_01_localvolumes.yaml"
  oc wait localvolume -n openshift-local-storage assisted-service --for condition=Available --timeout 10m || exit 1

  wait_for_crd "multiclusterengines.multicluster.openshift.io"
  apply_manifest "$mceManifests/agent_mce_1_02_mce.yaml"

  wait_for_crd "agentserviceconfigs.agent-install.openshift.io"
  apply_manifest "$mceManifests/agent_mce_1_03_agentserviceconfig.yaml"

  wait_for_crd "clusterimagesets.hive.openshift.io"
  apply_manifest "$mceManifests/agent_mce_1_04_clusterimageset.yaml"

  apply_manifest "$mceManifests/agent_mce_1_05_autoimport.yaml"
  oc wait -n multicluster-engine managedclusters local-cluster --for condition=ManagedClusterJoined=True --timeout 10m || exit 1

  echo "MCE deployment completed"
}

function mce_complete_deployment() {
  local mceManifests="${OCP_DIR}/mce"
  mkdir -p ${mceManifests}

  mce_prepare_postinstallation_manifests ${mceManifests}
  mce_apply_postinstallation_manifests ${mceManifests}
}
asset_dir="${1:-${OCP_DIR}}"
openshift_install="$(realpath "${OCP_DIR}/openshift-install")"

if [[ "${BOOT_MODE}" == "PXE" ]]; then
  create_pxe_files ${asset_dir} ${openshift_install}
fi

if [[ "${BOOT_MODE}" == "ISO" ]]; then
  create_image ${asset_dir} ${openshift_install}
fi

if [[ "${AGENT_DISABLE_AUTOMATED:-}" == "true" ]]; then
  disable_automated_installation
fi

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
if [ ! -f "${OCP_DIR}/auth/kubeadmin-password" ]; then
    oc patch --kubeconfig="${OCP_DIR}/auth/kubeconfig" secret -n kube-system kubeadmin --type json -p '[{"op": "replace", "path": "/data/kubeadmin", "value": "'"$(openssl rand -base64 18 | tr -d '\n' | tee "${OCP_DIR}/auth/kubeadmin-password" | htpasswd -nBi -C 10 "" | tr -d ':\n' | sed -e 's/\$2y\$/$2a$/' | base64 -w 0 -)"'"}]'
fi

if [ ! -z "${AGENT_DEPLOY_MCE}" ]; then
  mce_complete_deployment
fi

