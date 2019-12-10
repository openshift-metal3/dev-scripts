#!/bin/bash

set -o pipefail

function generate_assets() {
  rm -rf assets/generated && mkdir assets/generated
  for file in $(find assets/templates/ -iname '*.yaml' -type f -printf "%P\n"); do
      echo "Templating ${file} to assets/generated/${file}"
      cp assets/{templates,generated}/${file}

      for path in $(yq -r '.spec.config.storage.files[].path' assets/templates/${file} | cut -c 2-); do
          assets/yaml_patch.py "assets/generated/${file}" "/${path}" "$(cat assets/files/${path} | base64 -w0)"
      done
  done
}

function custom_ntp(){
  # TODO - consider adding NTP server config to install-config.yaml instead
  if [ -z ${NTP_SERVERS} ] && $(host clock.redhat.com > /dev/null); then
    NTP_SERVERS="clock.redhat.com"
  fi

  if [ "$NTP_SERVERS" ]; then
    cp assets/templates/99_worker-chronyd-custom.yaml.optional assets/generated/99_worker-chronyd-custom.yaml
    cp assets/templates/99_master-chronyd-custom.yaml.optional assets/generated/99_master-chronyd-custom.yaml
    NTPFILECONTENT=$(cat assets/files/etc/chrony.conf)
    for ntp in $(echo $NTP_SERVERS | tr ";" "\n"); do
      NTPFILECONTENT="${NTPFILECONTENT}"$'\n'"pool ${ntp} iburst"
    done
    NTPFILECONTENT=$(echo "${NTPFILECONTENT}" | base64 -w0)
    sed -i -e "s/NTPFILECONTENT/${NTPFILECONTENT}/g" assets/generated/*-chronyd-custom.yaml
  fi
}

function create_cluster() {
    local assets_dir

    assets_dir="$1"

    # Enable terraform debug logging
    export TF_LOG=DEBUG

    cp ${assets_dir}/install-config.yaml{,.tmp}
    $OPENSHIFT_INSTALLER --dir "${assets_dir}" --log-level=debug create manifests

    generate_assets
    custom_ntp
    bmo_config_map

    mkdir -p ${assets_dir}/openshift
    cp -rf assets/generated/*.yaml ${assets_dir}/openshift

    cp ${assets_dir}/install-config.yaml{.tmp,}
    if [ ! -z "${IGNITION_EXTRA:-}" ]; then
      $OPENSHIFT_INSTALLER --dir "${assets_dir}" --log-level=debug create ignition-configs
      if ! jq . ${IGNITION_EXTRA}; then
        echo "Error ${IGNITION_EXTRA} not valid json"
	exit 1
      fi
      mv ${assets_dir}/master.ign ${assets_dir}/master.ign.orig
      jq -s '.[0] * .[1]' ${IGNITION_EXTRA} ${assets_dir}/master.ign.orig | tee ${assets_dir}/master.ign
      mv ${assets_dir}/worker.ign ${assets_dir}/worker.ign.orig
      jq -s '.[0] * .[1]' ${IGNITION_EXTRA} ${assets_dir}/worker.ign.orig | tee ${assets_dir}/worker.ign
    fi
    $OPENSHIFT_INSTALLER --dir "${assets_dir}" --log-level=debug create cluster
}

function wait_for_json() {
    local name
    local url
    local curl_opts
    local timeout

    local start_time
    local curr_time
    local time_diff

    name="$1"
    url="$2"
    timeout="$3"
    shift 3
    curl_opts="$@"
    echo -n "Waiting for $name to respond"
    start_time=$(date +%s)
    until curl -g -X GET "$url" "${curl_opts[@]}" 2> /dev/null | jq '.' 2> /dev/null > /dev/null; do
        echo -n "."
        curr_time=$(date +%s)
        time_diff=$(($curr_time - $start_time))
        if [[ $time_diff -gt $timeout ]]; then
            echo "\nTimed out waiting for $name"
            return 1
        fi
        sleep 5
    done
    echo " Success!"
    return 0
}

function network_ip() {
    local network
    local rc

    network="$1"
    ip="$(sudo virsh net-dumpxml "$network" | "${PWD}/pyxpath" "//ip/@address" -)"
    rc=$?
    if [ $rc -ne 0 ]; then
        return $rc
    fi
    echo "$ip"
}

function master_node_val() {
    local n
    local val

    n="$1"
    val="$2"

    jq -r ".nodes[${n}].${val}" $MASTER_NODES_FILE
}

function master_node_map_to_install_config() {
    local num_masters
    num_masters="$1"

    for ((master_idx=0;master_idx<$1;master_idx++)); do
      name=$(master_node_val ${master_idx} "name")
      mac=$(master_node_val ${master_idx} "ports[0].address")

      driver=$(master_node_val ${master_idx} "driver")
      if [ $driver == "ipmi" ] ; then
          driver_prefix=ipmi
      elif [ $driver == "idrac" ] ; then
          driver_prefix=drac
      fi

      port=$(master_node_val ${master_idx} "driver_info.port // \"\"")
      username=$(master_node_val ${master_idx} "driver_info.username")
      password=$(master_node_val ${master_idx} "driver_info.password")
      address=$(master_node_val ${master_idx} "driver_info.address")

      cat << EOF
      - name: ${name}
        role: master
        bmc:
          address: ${address}
          username: ${username}
          password: ${password}
        bootMACAddress: ${mac}
        hardwareProfile: ${MASTER_HARDWARE_PROFILE:-default}
EOF

    done
}

function sync_repo_and_patch {
    REPO_PATH=${REPO_PATH:-$HOME}
    DEST="${REPO_PATH}/$1"
    echo "Syncing $1"

    if [ ! -d $DEST ]; then
        mkdir -p $DEST
        git clone $2 $DEST
    fi

    pushd $DEST

    git am --abort || true
    git checkout master
    git fetch origin
    git rebase origin/master
    if test "$#" -gt "2" ; then
        git branch -D metalkube || true
        git checkout -b metalkube

        shift; shift;
        for arg in "$@"; do
            curl -L $arg | git am
        done
    fi
    popd
}

function bmo_config_map {
    # Set default value for provisioning interface
    CLUSTER_PRO_IF=${CLUSTER_PRO_IF:-enp1s0}
    
    # Get Baremetal ip
    BAREMETAL_IP=$(ip -o -f inet addr show baremetal | awk '{print $4}' | tail -1 | cut -d/ -f1)
    
    mkdir -p ocp/deploy
    cp $SCRIPTDIR/metal3-config.yaml ocp/deploy
    sed -i "s#__RHCOS_IMAGE_URL__#${RHCOS_IMAGE_URL}#" ocp/deploy/metal3-config.yaml
    sed -i "s#provisioning_interface: \"ens3\"#provisioning_interface: \"${CLUSTER_PRO_IF}\"#" ocp/deploy/metal3-config.yaml
    sed -i "s#cache_url: \"http://192.168.111.1/images\"#cache_url: \"http://${BAREMETAL_IP}/images\"#" ocp/deploy/metal3-config.yaml
    
    cp ocp/deploy/metal3-config.yaml assets/generated/99_metal3-config.yaml
}
