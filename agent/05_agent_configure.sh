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
source $SCRIPTDIR/ocp_install_env.sh
source $SCRIPTDIR/oc_mirror.sh

early_deploy_validation

export CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE:-"cluster0"}

function add_ip_host_entry {
    ip=${1}
    hostname=${2}

    echo "${ip} ${hostname}">>"${OCP_DIR}"/hosts
}

function add_dns_entry {
    ip=${1}
    hostname=${2}

    # Add a DNS entry for this hostname if it's not already defined
    if ! $(sudo virsh net-dumpxml ${BAREMETAL_NETWORK_NAME} | xmllint --xpath "//dns/host[@ip = '${ip}']" - &> /dev/null); then
      sudo virsh net-update ${BAREMETAL_NETWORK_NAME} add dns-host  "<host ip='${ip}'> <hostname>${hostname}</hostname> </host>"  --live --config
    fi
}

function get_static_ips_and_macs() {

    AGENT_NODES_IPS=()
    AGENT_NODES_IPSV6=()
    AGENT_NODES_MACS=()
    AGENT_NODES_HOSTNAMES=()

    if [[ "$AGENT_STATIC_IP_NODE0_ONLY" = "true" ]]; then
        static_ips=1
    else
        static_ips=$NUM_MASTERS+$NUM_WORKERS
    fi

    if [[ $NETWORKING_MODE == "DHCP" ]]; then
      base_ip=20
    else
      # Set outside the range used for dhcp
      base_ip=80
    fi

    for (( i=0; i<${static_ips}; i++ ))
    do
        if [[ $i < $NUM_MASTERS ]]; then
            AGENT_NODES_HOSTNAMES+=($(printf ${MASTER_HOSTNAME_FORMAT} ${i}))
            cluster_name=${CLUSTER_NAME}_master_${i}
        else
	    worker_num=$((${i}-$NUM_MASTERS))
            AGENT_NODES_HOSTNAMES+=($(printf ${WORKER_HOSTNAME_FORMAT} ${worker_num}))
            cluster_name=${CLUSTER_NAME}_worker_${worker_num}
        fi

        ip=${base_ip}+${i}
        if [[ "$IP_STACK" = "v4" ]]; then
            AGENT_NODES_IPS+=($(nth_ip ${EXTERNAL_SUBNET_V4} ${ip}))
            add_dns_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
            add_ip_host_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
        elif [[ "$IP_STACK" = "v6" ]]; then
            AGENT_NODES_IPSV6+=($(nth_ip ${EXTERNAL_SUBNET_V6} ${ip}))
            add_dns_entry ${AGENT_NODES_IPSV6[i]} ${AGENT_NODES_HOSTNAMES[i]}
            add_ip_host_entry ${AGENT_NODES_IPSV6[i]} ${AGENT_NODES_HOSTNAMES[i]}
        else
	    # v4v6
            AGENT_NODES_IPS+=($(nth_ip ${EXTERNAL_SUBNET_V4} ${ip}))
            AGENT_NODES_IPSV6+=($(nth_ip $EXTERNAL_SUBNET_V6 ${ip}))
            add_dns_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
            add_ip_host_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
            add_dns_entry ${AGENT_NODES_IPSV6[i]} ${AGENT_NODES_HOSTNAMES[i]}
        fi

        # Get the generated mac addresses
        AGENT_NODES_MACS+=($(sudo virsh dumpxml $cluster_name | xmllint --xpath "string(//interface[descendant::source[@bridge = '${BAREMETAL_NETWORK_NAME}']]/mac/@address)" -))
    done
}

function generate_extra_cluster_manifests() {

  EXTRA_MANIFESTS_PATH="${OCP_DIR}/openshift"
  mkdir -p ${EXTRA_MANIFESTS_PATH}

cat > "${EXTRA_MANIFESTS_PATH}/agent-test.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: agent-test
  namespace: openshift-config
data:
  value: agent-test
EOF

  if [ ! -z "${AGENT_DEPLOY_MCE}" ]; then
    cp ${SCRIPTDIR}/agent/mce/agent_mce_0_*.yaml ${EXTRA_MANIFESTS_PATH}
  fi
}

function oc_mirror_mce() {
   tmpimageset=$(mktemp --tmpdir "mceimageset--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $tmpimageset"

   cat > "${tmpimageset}" << EOF
---
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v${OPENSHIFT_RELEASE_STREAM}
      packages:
        - name: multicluster-engine
---
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v${OPENSHIFT_RELEASE_STREAM}
      packages:
        - name: local-storage-operator
EOF

   pushd ${WORKING_DIR}
   oc mirror --dest-skip-tls --config ${tmpimageset} docker://${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}
   popd

}

function convert_icsp_to_registries_conf {

    # convert the following, for example, to registries.conf format
    # - mirrors:
    #   - virthost.ostest.test.metalkube.org:5000/openshift/release-images
    # source: quay.io/openshift-release-dev/ocp-release

    tmpregistriesfile=$(mktemp --tmpdir "registriesconf--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $tmpregistriesfile"
    while read -r line; do
        if [[ $line =~ "mirrors:" ]]; then
	   continue
        elif [[ $line =~ "source:" ]]; then
            source=$(echo ${line} | cut -d":" -f2 | xargs)

	    cat >> "${tmpregistriesfile}" << EOF
[[registry]]
prefix = ""
location = "${source}"
mirror-by-digest-only = true

[[registry.mirror]]
location = "${mirror}"

EOF
        else
	    mirror=$(echo ${line} | cut -d"-" --complement -f1 | xargs)
        fi
    done < ${1}

    cp ${tmpregistriesfile} ${1}
}

function get_mirror_info {

    # Get the ICSP info from the mirror log
    tmpmirrorinfo=$(mktemp --tmpdir "mirror--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $tmpmirrorinfo"
    if [[ ${MIRROR_COMMAND} == "oc-adm" ]]; then
       # Handle both ImageContentSources and ImageDigestSources in the output. In 4.14, `oc adm` was changed to
       # output ImageDigestSources, while prior to that it was ImageContentSources
       sed -n -E '/imageContentSources|imageDigestSources/,/^ *$/p' ${MIRROR_LOG_FILE} | tail -n+2 > ${tmpmirrorinfo}
    else
       results_dir=$(grep ICSP ${WORKING_DIR}/.oc-mirror.log | grep -o 'oc-mirror[^;]*')
       sed -ne '/repository/,/---/p' ${WORKING_DIR}/${results_dir}/imageContentSourcePolicy.yaml > ${tmpmirrorinfo}
       sed -i '/repositoryDigestMirrors/d;/---/d' ${tmpmirrorinfo}
    fi

    if [[ ${AGENT_USE_ZTP_MANIFESTS} == true ]]; then
        convert_icsp_to_registries_conf ${tmpmirrorinfo}
    fi

    export MIRROR_INFO_FILE=${tmpmirrorinfo}
}

function generate_cluster_manifests() {

  INSTALL_CONFIG_PATH="${OCP_DIR}"
  mkdir -p ${INSTALL_CONFIG_PATH}

  export MANIFESTS_PATH="${SCRIPTDIR}/${OCP_DIR}/cluster-manifests"
  mkdir -p ${MANIFESTS_PATH}

  export MIRROR_PATH="${SCRIPTDIR}/${OCP_DIR}/mirror"
  if [ ! -z "${MIRROR_IMAGES}" ]; then
    mkdir -p ${MIRROR_PATH}
  fi

  # Fetch current OpenShift version from the release payload
  export VERSION="$(openshift_version ${OCP_DIR})"
  export IMAGE=$(getReleaseImage)

  # set arrays as strings to pass in env
  nodes_ips=$(printf '%s,' "${AGENT_NODES_IPS[@]}")
  export AGENT_NODES_IPS_STR=${nodes_ips::-1}
  nodes_ipsv6=$(printf '%s,' "${AGENT_NODES_IPSV6[@]}")
  export AGENT_NODES_IPSV6_STR=${nodes_ipsv6::-1}
  nodes_macs=$(printf '%s,' "${AGENT_NODES_MACS[@]}")
  export AGENT_NODES_MACS_STR=${nodes_macs::-1}
  nodes_hostnames=$(printf '%s,' "${AGENT_NODES_HOSTNAMES[@]}")
  export AGENT_NODES_HOSTNAMES_STR=${nodes_hostnames::-1}

  if [[ "${NUM_MASTERS}" > "1" ]]; then
     export API_VIPS=${API_VIPS}
     export INGRESS_VIPS=${INGRESS_VIPS}
     export API_VIP=${API_VIPS%${VIPS_SEPARATOR}*}
     export INGRESS_VIP=${INGRESS_VIPS%${VIPS_SEPARATOR}*}
  fi

  if [[ ! -z "${MIRROR_IMAGES}" ]]; then
    # Store the certs for registry
    if [[ "${REGISTRY_BACKEND}" = "podman" ]]; then
       cp $REGISTRY_DIR/certs/$REGISTRY_CRT ${MIRROR_PATH}/ca-bundle.crt
    else
       cp ${WORKING_DIR}/quay-install/quay-rootCA/rootCA.pem ${MIRROR_PATH}/ca-bundle.crt
    fi

    get_mirror_info
  fi

  # Create manifests
  ansible-playbook -vvv \
          -e install_path=${SCRIPTDIR}/${INSTALL_CONFIG_PATH} \
          "${SCRIPTDIR}/agent/create-manifests-playbook.yaml"

}

write_pull_secret

# needed for assisted-service to run nmstatectl
# This is temporary and will go away when https://github.com/nmstate/nmstate is used
sudo yum install -y nmstate

get_static_ips_and_macs


if [[ ! -z "${MIRROR_IMAGES}" ]]; then
    if [[ ${MIRROR_COMMAND} == "oc-mirror" ]] && [[ ${AGENT_DEPLOY_MCE} == "true" ]]; then
        oc_mirror_mce
    fi
fi

if [[ "${NUM_MASTERS}" > "1" ]]; then
   set_api_and_ingress_vip
else
  # For SNO clusters, at least the api dns entry must be set
  # otherwise oc/openshift-install commands requiring the
  # kubeconfig will not work properly
  if [[ "$IP_STACK" = "v4" ]]; then
    ip=${AGENT_NODES_IPS[0]}
  else
    ip=${AGENT_NODES_IPSV6[0]}
  fi
  configure_dnsmasq ${ip} ""
fi

generate_cluster_manifests

if [ "$AGENT_E2E_TEST_TUI_BAD_DNS" = "true" ]; then
  # Create a bad dns configuration by changing master-0's
  # DNS server IP address
  if [[ "$IP_STACK" = "v4" ]]; then
    # from 192.168.111.1 to 192.168.111.2
    yq -i -y '.hosts[0].networkConfig["dns-resolver"].config.server[0] = "192.168.111.2"' "${OCP_DIR}/agent-config.yaml"
  fi
  if [[ "$IP_STACK" = "v6" ]]; then
    # from fd2e:6f44:5dd8:c956::1 to fd2e:6f44:5dd8:c956::2
    yq -i -y '.hosts[0].networkConfig["dns-resolver"].config.server[0] = "fd2e:6f44:5dd8:c956::2"' "${OCP_DIR}/agent-config.yaml"
  fi
  if [[ "$IP_STACK" = "v4v6" ]]; then
    # from 192.168.111.1 and fd2e:6f44:5dd8:c956::1 to 192.168.111.2 and fd2e:6f44:5dd8:c956::2
    yq -i -y '.hosts[0].networkConfig["dns-resolver"].config.server[0] = "192.168.111.2"' "${OCP_DIR}/agent-config.yaml"
    yq -i -y '.hosts[0].networkConfig["dns-resolver"].config.server[1] = "fd2e:6f44:5dd8:c956::2"' "${OCP_DIR}/agent-config.yaml"
  fi
fi

cat "${OCP_DIR}/agent-config.yaml"

generate_extra_cluster_manifests
