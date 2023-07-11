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

    if [ "${AGENT_USE_APPLIANCE_MODEL}" == true ]; then
      create_factory_image
    else
      create_automated_image
    fi
}

function create_automated_image() {
    "${openshift_install}" --dir="${asset_dir}" --log-level=debug agent create image
}

function create_factory_image() {
    config_image_drive="sdd"

    # The command to create the config-image must be run out of a separate asset directory using same assets
    mkdir -p ${config_image_dir}
    if [[ ${AGENT_USE_ZTP_MANIFESTS} == true ]]; then
       mkdir -p ${config_image_dir}/cluster-manifests
       cp ${asset_dir}/cluster-manifests/*.yaml ${config_image_dir}/cluster-manifests/
    else
       cp ${asset_dir}/*.yaml ${config_image_dir}
    fi

    # Create the unconfigured ignition and include it in an ISO
    "${openshift_install}" --dir="${asset_dir}" --log-level=debug agent create cluster-manifests

    # Remove any static networking configuration from unconfigured so that config-image sets it
    rm "${asset_dir}/cluster-manifests/nmstateconfig.yaml"
    rm "${asset_dir}/.openshift_install_state.json"

    "${openshift_install}" --dir="${asset_dir}" --log-level=debug agent create unconfigured-ignition
    base_iso_url=$(oc adm release info --registry-config "$PULL_SECRET_FILE" --image-for=machine-os-images --insecure=true $OPENSHIFT_RELEASE_IMAGE)
    oc image extract --path /coreos/coreos-$(uname -m).iso:$HOME/.cache/agent/image_cache --registry-config "$PULL_SECRET_FILE" --confirm $base_iso_url
    local agent_iso_abs_path="$(realpath "${OCP_DIR}")"
    podman run --privileged --rm -v /run/udev:/run/udev -v "${agent_iso_abs_path}:${agent_iso_abs_path}" -v "$HOME/.cache/agent/image_cache/:$HOME/.cache/agent/image_cache/" quay.io/coreos/coreos-installer:release iso ignition embed -f -i "${agent_iso_abs_path}/unconfigured-agent.ign" -o "${agent_iso_abs_path}/agent.iso" $HOME/.cache/agent/image_cache/coreos-$(uname -m).iso

    if [ "${AGENT_APPLIANCE_HOTPLUG}" != true ]; then
        create_config_image
    fi
}

function create_config_image() {

    "${openshift_install}" --log-level=debug --dir="${config_image_dir}" agent create config-image

    # Copy the auth files to OCP_DIR so wait-for command can access it
    cp -r ${config_image_dir}/auth ${asset_dir}
}

function set_device_config_image() {

    for (( n=0; n<${2}; n++ ))
    do
        name=${CLUSTER_NAME}_${1}_${n}
        sudo virsh change-media --domain ${name} --path ${config_image_drive} --source "${PWD}/${config_image_dir}/agentconfig.noarch.iso" --live --update
    done
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
	if [ "${AGENT_USE_APPLIANCE_MODEL}" == true ]; then
	    if [ "${AGENT_APPLIANCE_HOTPLUG}" == true ]; then
                # Add the device with no image. It will be added later using change-media when config-drive is created
                sudo virt-xml ${name} --add-device --disk device=cdrom,target.dev=${config_image_drive}
	    else
	        sudo virt-xml ${name} --add-device --disk "${config_image_dir}/agentconfig.noarch.iso",device=cdrom,target.dev=${config_image_drive}
	    fi
        fi
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
  local dir="${OCP_DIR}"
  if [[ "${AGENT_USE_APPLIANCE_MODEL}" == true ]]; then
     dir="${config_image_dir}"
  fi
  if ! "${openshift_install}" --dir="${dir}" --log-level=debug agent wait-for bootstrap-complete; then
      exit 1
  fi

  echo "Waiting for cluster ready... "
  "${openshift_install}" --dir="${dir}" --log-level=debug agent wait-for install-complete 2>&1 | grep --line-buffered -v 'password'
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

function run_agent_test_cases() {
  if [[ $AGENT_TEST_CASES =~ "bad_dns" ]]; then
    # wait 5 minutes for VMs to load and arrive at agent-tui check screen
    echo "Running test scenario: bad DNS record(s) in agent-config.yaml"
    echo "Waiting for 5 mins to arrive at agent-tui check screen"
    sleep 300

    # Take screenshots of console before fixing DNS. The screenshot may help us see if
    # agent-tui has reached the expected failure state.
    name=${CLUSTER_NAME}_master_0
    sudo virsh screenshot $name "${OCP_DIR}/${name}_console_screenshot_before_dns_fix.ppm"

    echo "Fixing DNS through agent-tui"
    # call script to fix DNS IP address on master-0
    ./agent/e2e/agent-tui/test-fix-wrong-dns.sh $CLUSTER_NAME $PROVISIONING_HOST_EXTERNAL_IP

    echo "Finished fixing DNS through agent-tui"
  fi
}

# Setup the environment to allow iPXE booting, by reusing libvirt native features
# to configure dnsmaq tftp server and pxe boot file
function setup_pxe_server() {
    mkdir -p ${PXE_SERVER_DIR}

    # Configure the DHCP options for PXE, based on the network type
    sudo virsh net-dumpxml ${BAREMETAL_NETWORK_NAME} > ${WORKING_DIR}/${BAREMETAL_NETWORK_NAME}

    local DHCP_PXE_OPTS="dhcp-boot=${PXE_SERVER_URL}/${PXE_BOOT_FILE}"
    if [[ "${IP_STACK}" = "v6" ]]; then
      DHCP_PXE_OPTS="dhcp-option=option6:bootfile-url,${PXE_SERVER_URL}/${PXE_BOOT_FILE}"
    fi
    sudo sed -i "/<\/dnsmasq:options>/i   <dnsmasq:option value='${DHCP_PXE_OPTS}'/>" ${WORKING_DIR}/${BAREMETAL_NETWORK_NAME}
    
    sudo virsh net-define ${WORKING_DIR}/${BAREMETAL_NETWORK_NAME}
    sudo virsh net-destroy ${BAREMETAL_NETWORK_NAME}
    sudo virsh net-start ${BAREMETAL_NETWORK_NAME}

    # Copy the generated PXE artifacts in the tftp server location
    cp ${SCRIPTDIR}/${OCP_DIR}/pxe/* ${PXE_SERVER_DIR}

    # Run a local http server to provide all the necessary PXE artifacts
    echo "package main; import (\"net/http\"); func main() { http.Handle(\"/\", http.FileServer(http.Dir(\"${PXE_SERVER_DIR}\"))); if err := http.ListenAndServe(\":${AGENT_PXE_SERVER_PORT}\", nil); err != nil { panic(err) } }" > ${PXE_SERVER_DIR}/agentpxeserver.go
    nohup go run ${PXE_SERVER_DIR}/agentpxeserver.go >/dev/null 2>&1 &
}

# Configure the instances for PXE booting
function agent_pxe_boot() {
    for (( n=0; n<${2}; n++ ))
      do
          name=${CLUSTER_NAME}_${1}_${n}
          sudo virt-xml ${name} --edit target=sda --disk="boot_order=1"
          sudo virt-xml ${name} --edit source=${BAREMETAL_NETWORK_NAME} --network="boot_order=2" --start
      done
}

asset_dir="${1:-${OCP_DIR}}"
config_image_dir="${1:-${OCP_DIR}/configimage}"
openshift_install="$(realpath "${OCP_DIR}/openshift-install")"

case "${AGENT_E2E_TEST_BOOT_MODE}" in
  "ISO" )
    create_image ${asset_dir} ${openshift_install}
    if [[ "${AGENT_DISABLE_AUTOMATED:-}" == "true" ]]; then
      disable_automated_installation
    fi

    attach_agent_iso master $NUM_MASTERS
    attach_agent_iso worker $NUM_WORKERS
    ;;

  "PXE" )
    create_pxe_files ${asset_dir} ${openshift_install}
    setup_pxe_server

    agent_pxe_boot master $NUM_MASTERS
    agent_pxe_boot worker $NUM_WORKERS
    ;;    
esac

if [ ! -z "${AGENT_TEST_CASES:-}" ]; then
  run_agent_test_cases
fi

if [ ! -z "${AGENT_ENABLE_GUI:-}" ]; then
  enable_assisted_service_ui
fi

if [[ "${AGENT_USE_APPLIANCE_MODEL}" == true ]] && [[ "${AGENT_APPLIANCE_HOTPLUG}" == true ]]; then

    # Wait for user input before creating config-image and mounting it to continue installation
    set +x
    config_image_msg="An unconfigured ISO has been installed on the hosts. Press any key to build a config-image and mount it to continue installation."
    echo -e "\n"
    read -n 1 -p "${config_image_msg}" input
    set -x

    create_config_image

    set_device_config_image master $NUM_MASTERS
    set_device_config_image worker $NUM_WORKERS
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
