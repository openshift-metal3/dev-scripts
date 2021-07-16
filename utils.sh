#!/bin/bash

set -o pipefail

function retry_with_timeout() {
  retries=$1
  timeout_duration=$2
  command=${*:3}

  for _ in $(seq "$retries"); do
    exit_code=0
    timeout "$timeout_duration" bash -c "$command" || exit_code=$?
    if (( exit_code == 0 )); then
      return 0
    fi
  done

  return $(( exit_code ))
}

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

function local_gateway_mode(){
  ASSESTS_DIR=$1
  cp assets/templates/cluster-network-00-gateway-mode.yaml.optional assets/generated/cluster-network-00-gateway-mode.yaml
}

function ensure_line() {
  file=$1
  line=$2

  grep -q "$line" $file || echo "$line" | sudo tee -a $file
}

function configure_chronyd() {
  sudo dnf install chrony && sudo systemctl enable chronyd

   ensure_line /etc/chrony.conf "allow ${EXTERNAL_SUBNET_V4}"
   ensure_line /etc/chrony.conf "allow ${EXTERNAL_SUBNET_V6}"
   ensure_line /etc/chrony.conf "allow ${PROVISIONING_NETWORK}"

  sudo systemctl restart chronyd

  if [ "$MANAGE_BR_BRIDGE" == "y" ];
  then
    sudo firewall-cmd --permanent --zone=libvirt --add-service=ntp
    sudo firewall-cmd --zone=libvirt --add-service=ntp
  else
    sudo firewall-cmd --permanent --add-service=ntp
    sudo firewall-cmd --add-service=ntp
  fi
}

function custom_ntp(){
  ASSESTS_DIR=$1
  # TODO - consider adding NTP server config to install-config.yaml instead
  if [ -z "${NTP_SERVERS}" ]; then
    if host clock.redhat.com; then
      NTP_SERVERS="clock.redhat.com"
    elif host pool.ntp.org; then
      NTP_SERVERS="pool.ntp.org"
    fi
  fi

  if [ -n "$NTP_SERVERS" ]; then
    cp assets/templates/98_worker-chronyd-custom.yaml.optional assets/generated/98_worker-chronyd-custom.yaml
    cp assets/templates/98_master-chronyd-custom.yaml.optional assets/generated/98_master-chronyd-custom.yaml
    NTPFILECONTENT=$(cat assets/files/etc/chrony.conf)
    for ntp in $(echo $NTP_SERVERS | tr ";" "\n"); do
      NTPFILECONTENT="${NTPFILECONTENT}"$'\n'"pool ${ntp} iburst"
    done
    NTPFILECONTENT=$(echo "${NTPFILECONTENT}" | base64 -w0)
    sed -i -e "s/NTPFILECONTENT/${NTPFILECONTENT}/g" assets/generated/*-chronyd-custom.yaml
    IGNITION_VERSION=$(yq -r .spec.config.ignition.version ${ASSESTS_DIR}/99_openshift-machineconfig_99-master-ssh.yaml)
    sed -i -e "s/IGNITION_VERSION/${IGNITION_VERSION}/g" assets/generated/*-chronyd-custom.yaml
    if [[ ${IGNITION_VERSION} =~ ^3\. ]]; then
      sed -i -e "/filesystem: root/d" assets/generated/*-chronyd-custom.yaml
    fi
  fi
}

function create_cluster() {
    local assets_dir

    assets_dir="$1"

    # Enable terraform debug logging
    export TF_LOG=DEBUG

    $OPENSHIFT_INSTALLER --dir "${assets_dir}" --log-level=debug create manifests

    mkdir -p ${assets_dir}/openshift
    generate_assets

    if [ -z "${NTP_SERVERS}" ];
    then
      export NTP_SERVERS="$PROVISIONING_HOST_EXTERNAL_IP"
    fi
    custom_ntp ${assets_dir}/openshift

    if [[ "${OVN_LOCAL_GATEWAY_MODE}" == "true" ]] && [[ "${NETWORK_TYPE}" == "OVNKubernetes" ]]; then
      local_gateway_mode ${assets_dir}/openshift
    fi
    generate_metal3_config

    find assets/generated -name '*.yaml' -exec cp -f {} ${assets_dir}/openshift \;

    if [[ "${IP_STACK}" == "v4v6" && "$(openshift_version $OCP_DIR)" =~ 4.[67] ]]; then
        # The IPv6DualStack feature is not on by default in 4.6 and 4.7 and needs
        # to be manually enabled
        cp assets/ipv6-dual-stack-no-upgrade.yaml ${assets_dir}/openshift/.
    fi

    if [[  ! -z "${ENABLE_CBO_TEST}" ]]; then
      # Create an empty image to be used by the CBO test deployment
      EMPTY_IMAGE=${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/empty:latest
      echo -e "FROM quay.io/quay/busybox\nCMD [\"sleep\", \"infinity\"]" | sudo podman build -t ${EMPTY_IMAGE} -f - .
      sudo podman push --tls-verify=false --authfile ${REGISTRY_CREDS} ${EMPTY_IMAGE} ${EMPTY_IMAGE}

      cp assets/metal3-cbo-deployment.yaml ${assets_dir}/openshift/.
    fi

    if [ ! -z "${ASSETS_EXTRA_FOLDER:-}" ]; then
      cp -rf ${ASSETS_EXTRA_FOLDER}/*.yaml ${assets_dir}/openshift/
    fi

    if [[ "$BMO_WATCH_ALL_NAMESPACES" == "true" ]]; then
        sed -i s/"watchAllNamespaces: false"/"watchAllNamespaces: true"/ "${assets_dir}/openshift/99_baremetal-provisioning-config.yaml"
    fi

    # Preserve the assets for debugging
    mkdir -p "${assets_dir}/saved-assets"
    cp -av "${assets_dir}/openshift" "${assets_dir}/saved-assets"
    cp -av "${assets_dir}/manifests" "${assets_dir}/saved-assets"

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

    trap auth_template_and_removetmp EXIT
    $OPENSHIFT_INSTALLER --dir "${assets_dir}" --log-level=debug create cluster
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
      boot_mode=$(node_val ${idx} "properties.boot_mode")
      if [[ "$boot_mode" == "null" ]]; then
             boot_mode="UEFI"
      fi

      cat << EOF
      - name: ${name}
        role: ${role}
        bmc:
          address: ${address}
          username: ${username}
          password: ${password}
          disableCertificateVerification: ${disable_certificate_verification}
        bootMACAddress: ${mac}
        bootMode: ${boot_mode}
EOF

        # FIXME(stbenjam) Worker code in installer should accept
        # "default" as well -- currently the mapping doesn't work,
        # so we use the raw value for BMO's default which is "unknown"
        if [[ "$role" == "master" ]]; then
            if [ -z "${MASTER_HARDWARE_PROFILE:-}" ]; then
                cat <<EOF
        rootDeviceHints:
          deviceName: "${ROOT_DISK_NAME}"
EOF
            else
                echo "WARNING: host profiles are deprecated, set ROOT_DISK_NAME instead of MASTER_HARDWARE_PROFILE." 1>&2
            fi
            echo "        hardwareProfile: ${MASTER_HARDWARE_PROFILE:-default}"
        else
            if [ -z "${WORKER_HARDWARE_PROFILE:-}" ]; then
                cat <<EOF
        rootDeviceHints:
          deviceName: "${ROOT_DISK_NAME}"
EOF
            else
                echo "WARNING: host profiles are deprecated, set ROOT_DISK_NAME instead of WORKER_HARDWARE_PROFILE." 1>&2
            fi
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

function generate_auth_template {
    set +x

    numPods=$(oc get pods -n openshift-machine-api -l baremetal.openshift.io/cluster-baremetal-operator=metal3-state -o json | jq '.items | length')
    if [ "$numPods" -eq '0' ]; then
      echo "Metal3 pod not found, skipping clouds.yaml generation"
      return
    fi

    # clouds.yaml
    OCP_VERSIONS_NOAUTH="4.3 4.4 4.5"

    VERSION=$(openshift_version $OCP_DIR)

    if [[ "$OCP_VERSIONS_NOAUTH" == *"$VERSION"* ]]; then
        go run metal3-templater.go "noauth" -template-file=clouds.yaml.template -provisioning-interface="$CLUSTER_PRO_IF" -provisioning-network="$PROVISIONING_NETWORK" -image-url="$MACHINE_OS_IMAGE_URL" -bootstrap-ip="$BOOTSTRAP_PROVISIONING_IP" -cluster-ip="$CLUSTER_PROVISIONING_IP" > clouds.yaml
    else
        IRONIC_USER=$((oc -n openshift-machine-api  get secret/metal3-ironic-password -o template --template '{{.data.username}}' || echo "") | base64 -d)
        IRONIC_PASSWORD=$((oc -n openshift-machine-api  get secret/metal3-ironic-password -o template --template '{{.data.password}}' || echo "") | base64 -d)
        IRONIC_CREDS="$IRONIC_USER:$IRONIC_PASSWORD"
        INSPECTOR_USER=$((oc -n openshift-machine-api  get secret/metal3-ironic-inspector-password -o template --template '{{.data.username}}' || echo "") | base64 -d)
        INSPECTOR_PASSWORD=$((oc -n openshift-machine-api  get secret/metal3-ironic-inspector-password -o template --template '{{.data.password}}' || echo "") | base64 -d)
        INSPECTOR_CREDS="$INSPECTOR_USER:$INSPECTOR_PASSWORD"
        CLUSTER_IRONIC_IP=$(oc get pods -n openshift-machine-api -l baremetal.openshift.io/cluster-baremetal-operator=metal3-state -o jsonpath="{.items[0].status.hostIP}" || echo "")

        # TODO(dtantsur): fetch the TLS public key, store it locally and link from clouds.yaml.

        if [ ! -z "${CLUSTER_IRONIC_IP}" ]; then
            go run metal3-templater.go "http_basic" -ironic-basic-auth="$IRONIC_CREDS" -inspector-basic-auth="$INSPECTOR_CREDS" -template-file=clouds.yaml.template -provisioning-interface="$CLUSTER_PRO_IF" -provisioning-network="$PROVISIONING_NETWORK" -image-url="$MACHINE_OS_IMAGE_URL" -bootstrap-ip="$BOOTSTRAP_PROVISIONING_IP" -cluster-ip="$CLUSTER_IRONIC_IP" > clouds.yaml
        else
            echo "Unable to read CLUSTER_IRONIC_IP - you may need to run generate_clouds_yaml.sh manually"
        fi

        BOOTSTRAP_VM_IP=$(bootstrap_ip)
        if [ ! -z "${BOOTSTRAP_VM_IP}" ]; then
            if ping -c 1 ${BOOTSTRAP_VM_IP}; then
                # From 4.7 basic_auth is also enabled on the bootstrap VM
                # There's a clouds.yaml we can copy in that case
                # FIXME: the sed of the URL is a workaround for
                # https://bugzilla.redhat.com/show_bug.cgi?id=1930240
                ($SSH core@${BOOTSTRAP_VM_IP} sudo cat /opt/metal3/auth/clouds.yaml || echo "") | sed "s/^clouds://" | sed "s/http:\/\/:/http:\/\/${BOOTSTRAP_VM_IP}:/" >> clouds.yaml
            fi
        fi
    fi

    # For compatibility with metal3-dev-env openstackclient.sh
    # which mounts a config dir into the ironic-client container
    mkdir -p _clouds_yaml
    ln -f clouds.yaml _clouds_yaml
    set -x
}

function generate_metal3_config {
    MACHINE_OS_IMAGE_URL="http:///$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_IMAGE_NAME}?sha256=${MACHINE_OS_BOOTSTRAP_IMAGE_SHA256}"
    # metal3-config.yaml
    mkdir -p ${OCP_DIR}/deploy
    go get github.com/apparentlymart/go-cidr/cidr github.com/openshift/installer/pkg/ipnet

    if [[ "$(openshift_version $OCP_DIR)" == "4.3" ]]; then
      go run metal3-templater.go noauth -template-file=metal3-config.yaml.template -provisioning-interface="$CLUSTER_PRO_IF" -provisioning-network="$PROVISIONING_NETWORK" -image-url="$MACHINE_OS_IMAGE_URL" -bootstrap-ip="$BOOTSTRAP_PROVISIONING_IP" -cluster-ip="$CLUSTER_PROVISIONING_IP" > ${OCP_DIR}/deploy/metal3-config.yaml
      cp ${OCP_DIR}/deploy/metal3-config.yaml assets/generated/98_metal3-config.yaml
    else
      echo "OpenShift Version is > 4.3; skipping config map"
    fi


    # Function to generate the bootstrap cloud information
    go run metal3-templater.go "bootstrap" -template-file=clouds.yaml.template -bootstrap-ip="$BOOTSTRAP_PROVISIONING_IP" > clouds.yaml

    mkdir -p _clouds_yaml
    ln -f clouds.yaml _clouds_yaml/clouds.yaml
}

function image_mirror_config {
    if [[ ! -z "${MIRROR_IMAGES}" || ! -z "${ENABLE_LOCAL_REGISTRY}" ]]; then
        INDENTED_CERT=$( cat $REGISTRY_DIR/certs/$REGISTRY_CRT | awk '{ print " ", $0 }' )
        if [[ ! -z "${MIRROR_IMAGES}" && ! -s ${MIRROR_LOG_FILE} ]]; then
            . /tmp/mirrored_release_image
            TAGGED=$(echo $MIRRORED_RELEASE_IMAGE | sed -e 's/release://')
            RELEASE=$(echo $MIRRORED_RELEASE_IMAGE | grep -o 'registry.ci.openshift.org[^":\@]\+')
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
    sudo chown -R $USER:$GROUP ${REGISTRY_DIR}

    pushd $REGISTRY_DIR/certs

    #
    # registry key and cert are generated if they don't exist
    #
    # NOTE(bnemec): When making changes to the certificate configuration,
    # increment the number in this filename and the REGISTRY_CRT value in common.sh
    REGISTRY_KEY=registry.2.key
    restart_registry=0
    if [[ ! -s ${REGISTRY_DIR}/certs/${REGISTRY_KEY} ]]; then
        restart_registry=1
        openssl genrsa -out ${REGISTRY_DIR}/certs/${REGISTRY_KEY} 2048
    fi

    if [[ ! -s ${REGISTRY_DIR}/certs/${REGISTRY_CRT} ]]; then
        restart_registry=1

        # Format names as DNS:name1,DNS:name2
        SUBJECT_ALT_NAME="DNS:$(echo $ALL_REGISTRY_DNS_NAMES | sed 's/ /,DNS:/g')"

        SSL_CONF=${REGISTRY_DIR}/certs/openssl.cnf
        cat > ${SSL_CONF} <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = US
ST = NC
L = Raleigh
O = Test Company
OU = Testing
CN = ${BASE_DOMAIN}

[SAN]
basicConstraints=CA:TRUE,pathlen:0
subjectAltName = ${SUBJECT_ALT_NAME}
EOF

        openssl req -x509 \
                -key ${REGISTRY_DIR}/certs/${REGISTRY_KEY} \
                -out  ${REGISTRY_DIR}/certs/${REGISTRY_CRT} \
                -days 365 \
                -config ${SSL_CONF} \
                -extensions SAN

        # Dump the certificate details to the log
        openssl x509 -in ${REGISTRY_DIR}/certs/${REGISTRY_CRT} -text
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
            ${DOCKER_REGISTRY_IMAGE}
    fi

}

function add_local_certificate_as_trusted() {
    REGISTRY_CONFIG="registry-config"
    oc create configmap ${REGISTRY_CONFIG} \
      --from-file=${LOCAL_REGISTRY_DNS_NAME}..${LOCAL_REGISTRY_PORT}=${REGISTRY_DIR}/certs/${REGISTRY_CRT} -n openshift-config
    oc patch image.config.openshift.io/cluster --patch "{\"spec\":{\"additionalTrustedCA\":{\"name\":\"${REGISTRY_CONFIG}\"}}}" --type=merge
}

function verify_pull_secret() {
  # Do some PULL_SECRET sanity checking
  if [[ "${OPENSHIFT_RELEASE_IMAGE}" == *"registry.ci.openshift.org"* ]]; then
      if [[ ${#CI_TOKEN} = 0 ]]; then
          error "Please login to https://console-openshift-console.apps.ci.l2s4.p1.openshiftapps.com/ and copy the token from the login command from the menu in the top right corner to set CI_TOKEN."
          exit 1
      fi
  fi

  if ! grep -q cloud.openshift.com "${PERSONAL_PULL_SECRET}"; then
      error "No cloud.openshift.com pull secret in ${PERSONAL_PULL_SECRET}"
      error "Get a valid pull secret (json string) from https://cloud.redhat.com/openshift/install/pull-secret"
      exit 1
  fi
}

function write_pull_secret() {
    if [ "${OPENSHIFT_CI}" == true ]; then
        # We don't need to fetch a personal pull secret with the
        # token, but we still need to merge what we're given with the
        # credentials for the local reigstry.
        jq -s '.[0] * .[1]' ${REGISTRY_CREDS} ${PERSONAL_PULL_SECRET} > ${PULL_SECRET_FILE}
        return
    fi

    verify_pull_secret

    # Get a current pull secret for registry.ci.openshift.org using the token
    tmpkubeconfig=$(mktemp --tmpdir "kubeconfig--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $tmpkubeconfig"
    oc login https://api.ci.l2s4.p1.openshiftapps.com:6443 --kubeconfig=$tmpkubeconfig --token=${CI_TOKEN}
    tmppullsecret=$(mktemp --tmpdir "pullsecret--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $tmppullsecret"
    oc registry login --kubeconfig=$tmpkubeconfig --to=$tmppullsecret

    # Combine the personal pull secret with the ones for the CI
    # registry and the local registry credentials.
    jq -s '.[0] * .[1] * .[2]' ${PERSONAL_PULL_SECRET} ${REGISTRY_CREDS} ${tmppullsecret} > ${PULL_SECRET_FILE}
}

function switch_to_internal_dns() {
  sudo mkdir -p /etc/NetworkManager/conf.d/
  ansible localhost -b -m ini_file -a "path=/etc/NetworkManager/conf.d/dnsmasq.conf section=main option=dns value=dnsmasq"
  if [ "$ADDN_DNS" ] ; then
    echo "server=$ADDN_DNS" | sudo tee /etc/NetworkManager/dnsmasq.d/upstream.conf
  fi
  if systemctl is-active --quiet NetworkManager; then
    sudo systemctl reload NetworkManager
  else
    sudo systemctl restart NetworkManager
  fi
}

function bootstrap_ip {
  if [[ "${IP_STACK}" == "v6" ]]; then
    pref_ip=ipv6
  else
    pref_ip=ipv4
  fi

  sudo virsh net-dhcp-leases ${BAREMETAL_NETWORK_NAME} \
                      | grep -v master \
                      | grep "${pref_ip}" \
                      | tail -n1 \
                      | awk '{print $5}' \
                      | sed -e 's/\(.*\)\/.*/\1/'
}

function image_for() {
    jq -r ".references.spec.tags[] | select(.name == \"$1\") | .from.name" ${OCP_DIR}/release_info.json
}


function wait_for_crd() {
  echo "Waiting for CRD ($1) to be defined"

  for i in {1..40}; do
    oc get "crd/$1" && break || sleep 10
  done

  oc wait --for condition=established --timeout=60s "crd/$1" || exit 1
}

_tmpfiles=
function removetmp(){
    [ -n "$_tmpfiles" ] && rm -rf $_tmpfiles || true
}

function auth_template_and_removetmp(){
    generate_auth_template
    removetmp
}

trap removetmp EXIT
