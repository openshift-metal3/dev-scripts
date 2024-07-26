source release_info.sh

eval "$(go env)"

function get_arch() {
    ARCH=$(uname -m)
    if [[ $ARCH == "aarch64" ]]; then
        ARCH="arm64"
    elif [[ $ARCH == "x86_64" ]]; then
        if [[ "$1" == "install_config" ]]; then
	    ARCH="amd64"
        fi
    fi
    echo $ARCH
}

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

    if [[ $cmd == "oc.rhel8" ]]; then
      cmd="oc"
    fi

    mv "${extract_dir}/${cmd}" "${outdir}"
}

# Let's always grab the `oc` from the release we're using.
function extract_oc() {
    extract_dir=$(mktemp --tmpdir -d "installer--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $extract_dir"
    if ! extract_command oc.rhel8 "$1" "${extract_dir}"; then
      extract_command oc "$1" "${extract_dir}"
    fi
    sudo mv "${extract_dir}/oc" /usr/local/bin
}

function extract_rhcos_json() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    baremetal_image=$(image_for baremetal-installer)
    baremetal_container=$(podman create --authfile "$PULL_SECRET_FILE" "$baremetal_image")

    # This is OK to fail as rhcos.json isn't available in every release,
    # we'll download it from github if it's not available
    podman cp "$baremetal_container":/var/cache/rhcos.json "$outdir" || true

    podman rm -f "$baremetal_container"
}

function baremetal_network_configuration() {
  if [[ "$(openshift_version $OCP_DIR)" == "4.3" ]]; then
    return
  fi

  if [[ "$PROVISIONING_NETWORK_PROFILE" == "Disabled" ]]; then
cat <<EOF
    provisioningNetwork: "${PROVISIONING_NETWORK_PROFILE}"
EOF
    if printf '%s\n4.6\n' "$(openshift_version)" | sort -V -C; then
cat <<EOF
    provisioningHostIP: "${CLUSTER_PROVISIONING_IP}"
    bootstrapProvisioningIP: "${BOOTSTRAP_PROVISIONING_IP}"
EOF
    fi
  else
cat <<EOF
    provisioningBridge: ${PROVISIONING_NETWORK_NAME}
    provisioningNetworkCIDR: $PROVISIONING_NETWORK
    provisioningNetworkInterface: $CLUSTER_PRO_IF
EOF
  fi

  if [ -n "${ENABLE_BOOTSTRAP_STATIC_IP}" ]; then
    if [[ "${IP_STACK}" = "v6" || "${IP_STACK}" = "v6v4" ]]; then
      BOOTSTRAP_IP=$(nth_ip $EXTERNAL_SUBNET_V6 $((idx + 9)))
    else
      BOOTSTRAP_IP=$(nth_ip $EXTERNAL_SUBNET_V4 $((idx + 9)))
    fi
cat <<EOF
    bootstrapExternalStaticIP: "${BOOTSTRAP_IP}"
    bootstrapExternalStaticGateway: "${PROVISIONING_HOST_EXTERNAL_IP}"
EOF
    if ! printf '%s\n4.13\n' "$(openshift_version)" | sort -V -C; then
cat <<EOF
    bootstrapExternalStaticDNS: "${PROVISIONING_HOST_EXTERNAL_IP}"
EOF
    fi
  fi
}

function dnsvip() {
  # dnsVIP was removed from 4.5
  if printf '%s\n4.4\n' "$(openshift_version)" | sort -V -C; then
cat <<EOF
    dnsVIP: ${DNS_VIP}
EOF
  fi
}

function external_mac() {
  if [ -n "$EXTERNAL_BOOTSTRAP_MAC" ] ; then
cat <<EOF
    externalMACAddress: $EXTERNAL_BOOTSTRAP_MAC
EOF
  fi
}


function renderVIPs() {
    # Arguments:
    #     First argument: field name
    #     Second argument: value for the field
    #
    # Description:
    #     This function helps to write in a YAML format multiple resources. (i.e: apiVIPs and ingressVIPs)
    #     Example: apiVIPs, "192.168.11.5, fd2e:6f44:5dd8:c956::15"
    #
    # Returns:
    #     YAML formatted resource
    FIELD_VALUES="${2}";

    echo "    ${1}"
    for data in ${FIELD_VALUES//${VIPS_SEPARATOR}/ }; do
        echo "    - ${data}"
    done
}

function setVIPs() {
    # Arguments:
    #     The type of VIP: apivips OR ingressvips
    #
    # Description:
    #     apiVIP and ingressVIP both has been DEPRECATED in 4.12 in favor of apiVIPs and ingressVIPs.
    #     This functions helps to write the new apiVIPs/ingressVIPs format or set the old fields.
    #
    # Returns:
    #     The YAML formatted APIVIP or INGRESSVIP (supports new and old format)
    case "${1}" in
    "apivips")
        if printf '4.12\n%s\n' "$(openshift_version)" | sort -V -C; then
            # OCP version is equals or newer as 4.12 and supports the new VIPs fields
            renderVIPs "apiVIPs:" "${API_VIPS}"
        else
            # OCP version is older as 4.12 and does not support the new VIPs fields
            echo "    apiVIP: ${API_VIPS%${VIPS_SEPARATOR}*}"
        fi
    ;;
    "ingressvips")
        if printf '4.12\n%s\n' "$(openshift_version)" | sort -V -C; then
            # OCP version is equals or newer as 4.12 and supports the new VIPs fields
            renderVIPs "ingressVIPs:" "${INGRESS_VIPS}"
        else
            # OCP version is older as 4.12 and does not support the new VIPs fields
            echo "    ingressVIP: ${INGRESS_VIPS%${VIPS_SEPARATOR}*}"
        fi
    ;;
    esac
}

function libvirturi() {
    if [[ "$REMOTE_LIBVIRT" -ne 0 ]]; then
cat <<EOF
    libvirtURI: qemu+ssh://${PROVISIONING_HOST_USER}@$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/system
EOF
    fi
}

function additional_trust_bundle() {
  if [[ ! -z "$ADDITIONAL_TRUST_BUNDLE" ]]; then
    if [[ -z "${MIRROR_IMAGES}" || "${MIRROR_IMAGES,,}" != "false" ]] && [[ -z "${ENABLE_LOCAL_REGISTRY}" ]]; then
      echo "additionalTrustBundle: |"
    fi
    awk '{ print " ", $0 }' "${ADDITIONAL_TRUST_BUNDLE}"
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
  elif [[ "${IP_STACK}" == "v6v4" ]]; then
cat <<EOF
  machineNetwork:
  - cidr: ${EXTERNAL_SUBNET_V6}
  - cidr: ${EXTERNAL_SUBNET_V4}
  clusterNetwork:
  - cidr: ${CLUSTER_SUBNET_V6}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V6}
  - cidr: ${CLUSTER_SUBNET_V4}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V4}
  serviceNetwork:
  - ${SERVICE_SUBNET_V6}
  - ${SERVICE_SUBNET_V4}
EOF
  else
    echo "Unexpected IP_STACK value: '${IP_STACK}'"
    exit 1
  fi
}

function override_openshift_sdn_deprecation() {
  # OpenShiftSDN is deprecated in 4.15 and later; if the user explicitly requests it,
  # we will override this deprecation (but not if they just defaulted to it).
  [[ "${ORIG_NETWORK_TYPE}" = "OpenShiftSDN" ]] && openshift_sdn_deprecated
}

function cluster_os_image() {
  if is_lower_version $(openshift_version) 4.10; then
cat <<EOF
    clusterOSImage: http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_IMAGE_NAME}?sha256=${MACHINE_OS_IMAGE_SHA256}
EOF
  fi
}

function generate_ocp_install_config() {
    local outdir

    outdir="$1"

    # when using local mirror set pull secret to just this mirror to
    # ensure we don't accidentally pull from upstream
    if [[ ! -z "${MIRROR_IMAGES}" && "${MIRROR_IMAGES,,}" != "false" ]]; then
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

    if override_openshift_sdn_deprecation; then
      # Claim we want OVNKubernetes in install-config; we will hack the generated
      # manifests later if OpenShiftSDN was explicitly requested.
      NETWORK_TYPE=OVNKubernetes
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
  architecture: $(get_arch install_config)
controlPlane:
  name: master
  replicas: ${NUM_MASTERS}
  architecture: $(get_arch install_config)
  platform:
    baremetal: {}
platform:
  baremetal:
$(libvirturi)
$(baremetal_network_configuration)
    externalBridge: ${BAREMETAL_NETWORK_NAME}
$(external_mac)
    bootstrapOSImage: http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}?sha256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}
$(cluster_os_image)
$(setVIPs apivips)
$(setVIPs ingressvips)
$(dnsvip)
    hosts:
EOF

  if [ -z "${HOSTS_SWAP_DEFINITION:-}" ]; then
    cat >> "${outdir}/install-config.yaml" << EOF
$(node_map_to_install_config_hosts $NUM_MASTERS 0 master)
$(node_map_to_install_config_hosts $NUM_WORKERS $NUM_MASTERS worker)
EOF
  else
    cat >> "${outdir}/install-config.yaml" << EOF
$(node_map_to_install_config_hosts $NUM_WORKERS $NUM_MASTERS worker)
$(node_map_to_install_config_hosts $NUM_MASTERS 0 master)
EOF
  fi

    cat >> "${outdir}/install-config.yaml" << EOF
$(image_mirror_config)
$(additional_trust_bundle)
pullSecret: |
  $(jq -c . $install_config_pull_secret)
sshKey: |
  ${SSH_PUB_KEY}
fips: ${FIPS_MODE:-false}
EOF

  if [[ ! -z "$INSTALLER_PROXY" ]]; then

    cat >> "${outdir}/install-config.yaml" << EOF
proxy:
  httpProxy: ${HTTP_PROXY}
  httpsProxy: ${HTTPS_PROXY}
  noProxy: ${NO_PROXY}
EOF
  fi

    cp "${outdir}/install-config.yaml" "${outdir}/install-config.yaml.save"
}

function generate_ocp_host_manifest() {
    local outdir

    outdir="$1"
    host_input="$2"
    host_output="$3"
    namespace="$4"

    mkdir -p "${outdir}"
    rm -f "${outdir}/extra_hosts.yaml"

    mkdir -p "${outdir}/extras"
    rm -f "${outdir}/extras/*"

    worker_index=0
    jq --raw-output '.[] | .name + " " + .ports[0].address + " " + .driver_info.username + " " + .driver_info.password + " " + .driver_info.address' $host_input \
       | while read name mac username password address ; do

        encoded_username=$(echo -n "$username" | base64)
        encoded_password=$(echo -n "$password" | base64)

        secret="---
apiVersion: v1
kind: Secret
metadata:
  name: ${name}-bmc-secret
  namespace: $namespace
type: Opaque
data:
  username: $encoded_username
  password: $encoded_password
"
        bmh="---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: $name
  namespace: $namespace
spec:
  online: ${EXTRA_WORKERS_ONLINE_STATUS}
  bootMACAddress: $mac
  bmc:
    address: $address
    credentialsName: ${name}-bmc-secret"

        echo "${secret}${bmh}" >> "${outdir}/${host_output}"

        # Extra files will be used later to generate a secret used by e2e tests
        echo "${secret}" >> "${outdir}/extras/extraworker-${worker_index}-secret"
        echo "${bmh}" >> "${outdir}/extras/extraworker-${worker_index}-bmh"
        ((worker_index+=1))
    done
}
