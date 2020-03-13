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

    $OPENSHIFT_INSTALLER --dir "${assets_dir}" --log-level=debug create manifests

    generate_assets
    custom_ntp
    generate_templates

    mkdir -p ${assets_dir}/openshift
    cp -rf assets/generated/*.yaml ${assets_dir}/openshift

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
    $OPENSHIFT_INSTALLER --dir "${assets_dir}" --log-level=debug create cluster || true
    # FIXME(stbenjam): Deploying workers as part of the install now
    # seems to reliably exceed the 30 minute limit. We're going to have
    # to implement a 60-minute timeout for install-complete on baremetal
    # I think.
    $OPENSHIFT_INSTALLER --dir "${assets_dir}" --log-level=debug wait-for install-complete
}

function ipversion(){
    if [[ $1 =~ : ]] ; then
        echo 6
        exit
    fi
    echo 4
}

function wrap_if_ipv6(){
    if [ $(ipversion $1) == 6 ] ; then
        echo "[$1]"
        exit
    fi
    echo "$1"
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

function node_val() {
    local n
    local val

    n="$1"
    val="$2"

    jq -r ".nodes[${n}].${val}" $NODES_FILE
}

function node_map_to_install_config_hosts() {
    local num_hosts
    num_hosts="$1"
    start_idx="$2"
    role="$3"

    for ((idx=$start_idx;idx<$(($1 + $start_idx));idx++)); do
      name=$(node_val ${idx} "name")
      mac=$(node_val ${idx} "ports[0].address")

      driver=$(node_val ${idx} "driver")
      if [ $driver == "ipmi" ] ; then
          driver_prefix=ipmi
      elif [ $driver == "idrac" ] ; then
          driver_prefix=drac
      fi

      port=$(node_val ${idx} "driver_info.port // \"\"")
      username=$(node_val ${idx} "driver_info.username")
      password=$(node_val ${idx} "driver_info.password")
      address=$(node_val ${idx} "driver_info.address")
      disable_certificate_verification=$(node_val ${idx} "driver_info.disable_certificate_verification")

      cat << EOF
      - name: ${name}
        role: ${role}
        bmc:
          address: ${address}
          username: ${username}
          password: ${password}
          disableCertificateVerification: ${disable_certificate_verification}
        bootMACAddress: ${mac}
EOF

        # FIXME(stbenjam) Worker code in installer should accept
        # "default" as well -- currently the mapping doesn't work,
        # so we use the raw value for BMO's default which is "unknown"
        if [[ "$role" == "master" ]]; then
          echo "        hardwareProfile: ${MASTER_HARDWARE_PROFILE:-default}"
        else
          echo "        hardwareProfile: ${WORKER_HARDWARE_PROFILE:-unknown}"
        fi
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

function generate_templates {
    MACHINE_OS_IMAGE_URL="http:///$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_IMAGE_NAME}?sha256=${MACHINE_OS_BOOTSTRAP_IMAGE_SHA256}"

    # metal3-config.yaml
    mkdir -p ${OCP_DIR}/deploy
    go get github.com/apparentlymart/go-cidr/cidr github.com/openshift/installer/pkg/ipnet

    if [[ "$OPENSHIFT_VERSION" == "4.3" ]]; then
      go run metal3-templater.go metal3-config.yaml.template "$CLUSTER_PRO_IF" "$PROVISIONING_NETWORK" "$MACHINE_OS_IMAGE_URL" > ${OCP_DIR}/deploy/metal3-config.yaml
      cp ${OCP_DIR}/deploy/metal3-config.yaml assets/generated/99_metal3-config.yaml
    else
      echo "OpenShift Version is > 4.3; skipping config map"
    fi

    # clouds.yaml
    go run metal3-templater.go clouds.yaml.template "$CLUSTER_PRO_IF" "$PROVISIONING_NETWORK" "$MACHINE_OS_IMAGE_URL" > clouds.yaml
    # For compatibility with metal3-dev-env openstackclient.sh
    # which mounts a config dir into the ironic-client container
    mkdir -p _clouds_yaml
    cp clouds.yaml _clouds_yaml
}

function image_mirror_config {
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        TAG=$( echo $OPENSHIFT_RELEASE_IMAGE | sed -e 's/[[:alnum:]/.-]*release://' )
        TAGGED=$(echo $OPENSHIFT_RELEASE_IMAGE | sed -e 's/release://')
        RELEASE=$(echo $OPENSHIFT_RELEASE_IMAGE | grep -o 'registry.svc.ci.openshift.org[^":]\+')
        INDENTED_CERT=$( cat $REGISTRY_DIR/certs/$REGISTRY_CRT | awk '{ print " ", $0 }' )
        MIRROR_LOG_FILE=/tmp/tmp_image_mirror-${TAG}.log
        if [ ! -s ${MIRROR_LOG_FILE} ]; then
            cat << EOF
imageContentSources:
- mirrors:
    - ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image
  source: ${RELEASE}
- mirrors:
    - ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image
  source: ${TAGGED}
additionalTrustBundle: |
${INDENTED_CERT}
EOF
        else
            cat ${MIRROR_LOG_FILE} | sed -n '/To use the new mirrored repository to install/,/To use the new mirrored repository for upgrades/p' |\
                sed -e '/^$/d' -e '/To use the new mirrored repository/d'
            cat << EOF
additionalTrustBundle: |
${INDENTED_CERT}
EOF
        fi
    fi
}

function setup_local_registry() {

    # httpd-tools provides htpasswd utility
    sudo yum install -y httpd-tools

    sudo mkdir -pv ${REGISTRY_DIR}/{auth,certs,data}
    sudo chown -R $USER:$USER ${REGISTRY_DIR}

    pushd $REGISTRY_DIR/certs
    SSL_HOST_NAME="${LOCAL_REGISTRY_DNS_NAME}"

    if ipcalc -c $SSL_HOST_NAME; then
        SSL_EXT_8="subjectAltName = IP:${SSL_HOST_NAME}"
        SSL_EXT_7="subjectAltName = IP:${SSL_HOST_NAME}"
    else
        SSL_EXT_8="subjectAltName = DNS:${SSL_HOST_NAME}"
        SSL_EXT_7="subjectAltName = DNS:${SSL_HOST_NAME}"
    fi

    #
    # registry key and cert are generated if they don't exist
    #
    # NOTE(bnemec): When making changes to the certificate configuration,
    # increment the number in this filename and the REGISTRY_CRT value in common.sh
    REGISTRY_KEY=registry.1.key
    restart_registry=0
    if [[ ! -s ${REGISTRY_DIR}/certs/${REGISTRY_KEY} ]]; then
        restart_registry=1
        openssl genrsa -out ${REGISTRY_DIR}/certs/${REGISTRY_KEY} 2048
    fi

    if [[ ! -s ${REGISTRY_DIR}/certs/${REGISTRY_CRT} ]]; then
        restart_registry=1
        if [ "${RHEL8}" = "True" ] || [ "${CENTOS8}" = "True" ]; then
            openssl req -x509 \
                -key ${REGISTRY_DIR}/certs/${REGISTRY_KEY} \
                -out ${REGISTRY_DIR}/certs/${REGISTRY_CRT} \
                -days 365 \
                -addext "${SSL_EXT_8}" \
                -subj "/C=US/ST=NC/L=Raleigh/O=Test Company/OU=Testing/CN=${SSL_HOST_NAME}"
        else
            SSL_TMP_CONF=$(mktemp 'my-ssl-conf.XXXXXX')
            cat > ${SSL_TMP_CONF} <<EOF
[req]
distinguished_name = req_distinguished_name

[req_distinguished_name]
CN = ${SSL_HOST_NAME}

[SAN]
basicConstraints=CA:TRUE,pathlen:0
${SSL_EXT_7}
EOF

            openssl req -x509 \
                -key ${REGISTRY_DIR}/certs/${REGISTRY_KEY} \
                -out  ${REGISTRY_DIR}/certs/${REGISTRY_CRT} \
                -days 365 \
                -config ${SSL_TMP_CONF} \
                -extensions SAN \
                -subj "/C=US/ST=NC/L=Raleigh/O=Test Company/OU=Testing/CN=${SSL_HOST_NAME}"
        fi
    fi

    popd

    htpasswd -bBc ${REGISTRY_DIR}/auth/htpasswd ${REGISTRY_USER} ${REGISTRY_PASS}

    sudo cp ${REGISTRY_DIR}/certs/${REGISTRY_CRT} /etc/pki/ca-trust/source/anchors/
    sudo update-ca-trust

    reg_state=$(sudo podman inspect registry --format  "{{.State.Status}}" || echo "error")

    # if container doesn't run or has different SSL cert that preent in ${REGISTRY_DIR}/certs/
    #   restart it

    if [[ "$reg_state" != "running" || $restart_registry -eq 1 ]]; then
        sudo podman rm registry -f || true

        sudo podman run -d --name registry --net=host --privileged \
            -v ${REGISTRY_DIR}/data:/var/lib/registry:z \
            -v ${REGISTRY_DIR}/auth:/auth:z \
            -e "REGISTRY_AUTH=htpasswd" \
            -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
            -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
            -v ${REGISTRY_DIR}/certs:/certs:z \
            -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${REGISTRY_CRT} \
            -e REGISTRY_HTTP_TLS_KEY=/certs/${REGISTRY_KEY} \
            docker.io/registry:latest
    fi

}
