eval "$(go env)"

function extract_command() {
    local release_image
    local cmd
    local outdir
    local extract_dir

    cmd="$1"
    release_image="$2"
    outdir="$3"

    extract_dir=$(mktemp --tmpdir -d "installer--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $extract_dir"

    oc adm release extract --registry-config "${PULL_SECRET_FILE}" --command=$cmd --to "${extract_dir}" ${release_image}

    mv "${extract_dir}/${cmd}" "${outdir}"
}

# Let's always grab the `oc` from the release we're using.
function extract_oc() {
    extract_dir=$(mktemp --tmpdir -d "installer--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $extract_dir"
    extract_command oc "$1" "${extract_dir}"
    sudo mv "${extract_dir}/oc" /usr/local/bin
}

function extract_installer() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    extract_command openshift-baremetal-install "$1" "$2"
}

function extract_rhcos_json() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    baremetal_image=$(oc adm release info --image-for=baremetal-installer --registry-config "$PULL_SECRET_FILE" "$release_image")
    baremetal_container=$(podman create --authfile "$PULL_SECRET_FILE" "$baremetal_image")

    # This is OK to fail as rhcos.json isn't available in every release,
    # we'll download it from github if it's not available
    podman cp "$baremetal_container":/var/cache/rhcos.json "$outdir" || true

    podman rm -f "$baremetal_container"
}

function clone_installer() {
  # Clone repo, if not already present
  if [[ ! -d $OPENSHIFT_INSTALL_PATH ]]; then
    sync_repo_and_patch go/src/github.com/openshift/installer https://github.com/openshift/installer.git
  fi
}

function build_installer() {
  # Build installer
  pushd .
  cd $OPENSHIFT_INSTALL_PATH
  TAGS="libvirt baremetal" hack/build.sh
  popd
  cp "$OPENSHIFT_INSTALL_PATH/data/data/rhcos.json" "$OCP_DIR"
}

function baremetal_network_configuration() {
  if [[ "$OPENSHIFT_VERSION" == "4.3" ]]; then
    return
  fi

  if [[ "$PROVISIONING_NETWORK_PROFILE" == "Disabled" ]]; then
cat <<EOF
    provisioningNetwork: "${PROVISIONING_NETWORK_PROFILE}"
    provisioningHostIP: "${CLUSTER_PROVISIONING_IP}"
    bootstrapProvisioningIP: "${BOOTSTRAP_PROVISIONING_IP}"
EOF
  else
cat <<EOF
    provisioningBridge: ${PROVISIONING_NETWORK_NAME}
    provisioningNetworkCIDR: $PROVISIONING_NETWORK
    provisioningNetworkInterface: $CLUSTER_PRO_IF
EOF
  fi
}

function libvirturi() {
    if [[ "$REMOTE_LIBVIRT" -ne 0 ]]; then
cat <<EOF
    libvirtURI: qemu+ssh://${PROVISIONING_HOST_USER}@$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/system
EOF
    fi
}

function cluster_network() {
  if [[ "${IP_STACK}" == "v4" ]]; then
cat <<EOF
  machineNetwork:
  - cidr: ${EXTERNAL_SUBNET_V4}
  clusterNetwork:
  - cidr: ${CLUSTER_SUBNET_V4}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V4}
  serviceNetwork:
  - ${SERVICE_SUBNET_V4}
EOF
  elif [[ "${IP_STACK}" == "v6" ]]; then
cat <<EOF
  machineNetwork:
  - cidr: ${EXTERNAL_SUBNET_V6}
  clusterNetwork:
  - cidr: ${CLUSTER_SUBNET_V6}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V6}
  serviceNetwork:
  - ${SERVICE_SUBNET_V6}
EOF
  elif [[ "${IP_STACK}" == "v4v6" ]]; then
cat <<EOF
  machineNetwork:
  - cidr: ${EXTERNAL_SUBNET_V4}
  - cidr: ${EXTERNAL_SUBNET_V6}
  clusterNetwork:
  - cidr: ${CLUSTER_SUBNET_V4}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V4}
  - cidr: ${CLUSTER_SUBNET_V6}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V6}
  serviceNetwork:
  - ${SERVICE_SUBNET_V4}
  - ${SERVICE_SUBNET_V6}
EOF
  else
    echo "Unexpected IP_STACK value: '${IP_STACK}'"
    exit 1
  fi
}

function generate_ocp_install_config() {
    local outdir

    outdir="$1"

    # when using local mirror set pull secret to just this mirror to
    # ensure we don't accidentally pull from upstream
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        install_config_pull_secret="${REGISTRY_CREDS}"
    else
        install_config_pull_secret="${PULL_SECRET_FILE}"
    fi

    mkdir -p "${outdir}"

    # IPv6 network config validation
    if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
      if [[ "${NETWORK_TYPE}" != "OVNKubernetes" ]]; then
        echo "NETWORK_TYPE must be OVNKubernetes when using IPv6"
        exit 1
      fi
    fi

    cat > "${outdir}/install-config.yaml" << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
networking:
  networkType: ${NETWORK_TYPE}
$(cluster_network)
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: $NUM_WORKERS
controlPlane:
  name: master
  replicas: ${NUM_MASTERS}
  platform:
    baremetal: {}
platform:
  baremetal:
$(libvirturi)
$(baremetal_network_configuration)
    externalBridge: ${BAREMETAL_NETWORK_NAME}
    bootstrapOSImage: http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}?sha256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}
    clusterOSImage: http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_IMAGE_NAME}?sha256=${MACHINE_OS_IMAGE_SHA256}
    apiVIP: ${API_VIP}
    ingressVIP: ${INGRESS_VIP}
    dnsVIP: ${DNS_VIP}
    hosts:
$(node_map_to_install_config_hosts $NUM_MASTERS 0 master)
$(node_map_to_install_config_hosts $NUM_WORKERS $NUM_MASTERS worker)
$(image_mirror_config)
pullSecret: |
  $(jq -c . $install_config_pull_secret)
sshKey: |
  ${SSH_PUB_KEY}
fips: ${FIPS_MODE:-false}
EOF

    cp "${outdir}/install-config.yaml" "${outdir}/install-config.yaml.save"
}

function generate_ocp_host_manifest() {
    local outdir

    outdir="$1"
    host_input="$2"

    mkdir -p "${outdir}"
    rm -f "${outdir}/extra_hosts.yaml"

    jq --raw-output '.[] | .name + " " + .ports[0].address + " " + .driver_info.username + " " + .driver_info.password + " " + .driver_info.address' $host_input \
       | while read name mac username password address ; do

        encoded_username=$(echo -n "$username" | base64)
        encoded_password=$(echo -n "$password" | base64)

    cat >> "${outdir}/extra_host_manifests.yaml" << EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ${name}-bmc-secret
  namespace: openshift-machine-api
type: Opaque
data:
  username: $encoded_username
  password: $encoded_password

---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: $name
  namespace: openshift-machine-api
spec:
  online: true
  bootMACAddress: $mac
  bmc:
    address: $address
    credentialsName: ${name}-bmc-secret
EOF

    done
}
