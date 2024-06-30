#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh
source $SCRIPTDIR/release_info.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/agent/common.sh
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

    # Add entries to etc/hosts for SNO IPV6 to sucessfully run the openshift conformance tests
    if [[ $NUM_MASTERS == 1 && $IP_STACK == "v6" ]]; then
      AGENT_NODE0_IPSV6=${ip}
      echo "${ip} console-openshift-console.apps.${CLUSTER_DOMAIN}" | sudo tee -a /etc/hosts
      echo "${ip} oauth-openshift.apps.${CLUSTER_DOMAIN}" | sudo tee -a /etc/hosts
      echo "${ip} thanos-querier-openshift-monitoring.apps.${CLUSTER_DOMAIN}" | sudo tee -a /etc/hosts
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
        if [[ ! -z "${BOND_PRIMARY_INTERFACE:-}" ]]; then
	   # For a bond, a random mac is added for the 2nd interface
	   AGENT_NODES_MACS+=($(sudo virsh domiflist ${cluster_name} | grep ${BAREMETAL_NETWORK_NAME} | grep -v ${AGENT_NODES_MACS[-1]} | awk '{print $5}'))
        fi
    done
}

function generate_extra_cluster_manifests() {

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
  if [[ ! -z "${MIRROR_IMAGES}" && "${MIRROR_IMAGES,,}" != "false" ]]; then
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

  if [[ "$IP_STACK" = "v4v6" ]]; then
     export PROVISIONING_HOST_EXTERNAL_IP_DUALSTACK=$(nth_ip $EXTERNAL_SUBNET_V6 1)
  fi

  if [[ ! -z "${MIRROR_IMAGES}" && "${MIRROR_IMAGES,,}" != "false" ]]; then
    # Store the certs for registry
    if [[ "${REGISTRY_BACKEND}" = "podman" ]]; then
       cp $REGISTRY_DIR/certs/$REGISTRY_CRT ${MIRROR_PATH}/ca-bundle.crt
    else
       cp ${WORKING_DIR}/quay-install/quay-rootCA/rootCA.pem ${MIRROR_PATH}/ca-bundle.crt
    fi

    get_mirror_info
  fi

  set +x
  # Set BMC info
  nodes_bmc_usernames=$(printf '%s,' "${AGENT_NODES_BMC_USERNAMES[@]}")
  export AGENT_NODES_BMC_USERNAMES_STR=${nodes_bmc_usernames::-1}
  nodes_bmc_passwords=$(printf '%s,' "${AGENT_NODES_BMC_PASSWORDS[@]}")
  export AGENT_NODES_BMC_PASSWORDS_STR=${nodes_bmc_passwords::-1}
  nodes_bmc_addresses=$(printf '%s,' "${AGENT_NODES_BMC_ADDRESSES[@]}")
  export AGENT_NODES_BMC_ADDRESSES_STR=${nodes_bmc_addresses::-1}
  set -x

  # Create manifests
  ansible-playbook -vvv \
          -e install_path=${SCRIPTDIR}/${INSTALL_CONFIG_PATH} \
          "${SCRIPTDIR}/agent/create-manifests-playbook.yaml"
}

function add_haproxy_server_lines() {
  num_servers=${1}
  type=${2}
  port=${3}

  # AGENT_NODES_IPS has master ip addresses listed first
  # and worker ip addresses listed second.
  # Depending on the $type, here we find the right
  # slice of the array to iterate over.
  if [[ "$type" == "master" ]]; then
    starting=0
  else
    # $type == "worker"
    starting=$NUM_MASTERS
    num_servers=$((NUM_MASTERS + num_servers))
  fi

  for (( n=$starting; n<${num_servers}; n++ ))
  do
    cat << EOF >> ${WORKING_DIR}/haproxy.cfg
  server ${type}-$n ${AGENT_NODES_IPS[n]}:${port} check inter 1s
EOF
  done
}

function enable_load_balancer() {
  local api_ip=${1}
  local load_balancer_ip=${2}
  local HTTP_PORT=80

  if [[ "${AGENT_PLATFORM_TYPE}" == "none" || "${AGENT_PLATFORM_TYPE}" == "external" ]] && [[ "${NUM_MASTERS}" > "1" ]]; then

    # setup haproxy as the load balancer
    if [[ "${IP_STACK}" == "v6" ]]; then
      # The "wildcard" is different depending on IP stack.
      # See http://docs.haproxy.org/1.6/configuration.html#4.2-bind
      export HAPROXY_WILDCARD="[::]"
    else
      export HAPROXY_WILDCARD="*"
    fi

    cat << EOF >> ${WORKING_DIR}/haproxy.cfg
defaults
    mode                    tcp
    log                     global
    timeout connect         10s
    timeout client          1m
    timeout server          1m
frontend stats
  bind *:1936
  mode            http
  log             global
  maxconn 10
  stats enable
  stats hide-version
  stats refresh 30s
  stats show-node
  stats show-desc Stats for ocp4 cluster
  stats auth admin:ocp4
  stats uri /stats
listen api-server-${KUBE_API_PORT}
  bind ${HAPROXY_WILDCARD}:${KUBE_API_PORT}
  mode tcp
EOF
    add_haproxy_server_lines $NUM_MASTERS "master" "${KUBE_API_PORT}"

    cat << EOF >> ${WORKING_DIR}/haproxy.cfg
listen machine-config-server-${MACHINE_CONFIG_SERVER_PORT}
  bind ${HAPROXY_WILDCARD}:${MACHINE_CONFIG_SERVER_PORT}
  mode tcp
EOF
    add_haproxy_server_lines $NUM_MASTERS "master" "${MACHINE_CONFIG_SERVER_PORT}"

    if [[ "${NUM_WORKERS}" > "0" ]]; then
      # Cluster contains workers, ingress and HTTP traffic goes to them
      cat << EOF >> ${WORKING_DIR}/haproxy.cfg
listen ingress-router-${INGRESS_ROUTER_PORT}
  bind ${HAPROXY_WILDCARD}:${INGRESS_ROUTER_PORT}
  mode tcp
  balance source
EOF
      add_haproxy_server_lines $NUM_WORKERS "worker" "${INGRESS_ROUTER_PORT}"

      cat << EOF >> ${WORKING_DIR}/haproxy.cfg
listen ingress-router-${HTTP_PORT}
  bind ${HAPROXY_WILDCARD}:${HTTP_PORT}
  mode tcp
  balance source
EOF
      add_haproxy_server_lines $NUM_WORKERS "worker" "${HTTP_PORT}"
    else
      # Cluster does not contain workers, ingress and HTTP traffic goes to
      # control plane
      cat << EOF >> ${WORKING_DIR}/haproxy.cfg
listen ingress-router-${INGRESS_ROUTER_PORT}
  bind ${HAPROXY_WILDCARD}:${INGRESS_ROUTER_PORT}
  mode tcp
  balance source
EOF
      add_haproxy_server_lines $NUM_MASTERS "master" "${INGRESS_ROUTER_PORT}"

      cat << EOF >> ${WORKING_DIR}/haproxy.cfg
listen ingress-router-${HTTP_PORT}
  bind ${HAPROXY_WILDCARD}:${HTTP_PORT}
  mode tcp
  balance source
EOF
      add_haproxy_server_lines $NUM_MASTERS "master" "${HTTP_PORT}"
    fi

    sudo firewall-cmd --zone libvirt --add-port=${MACHINE_CONFIG_SERVER_PORT}/tcp
    sudo firewall-cmd --zone libvirt --add-port=${KUBE_API_PORT}/tcp
    sudo firewall-cmd --zone libvirt --add-port=${INGRESS_ROUTER_PORT}/tcp
    sudo podman run -d  --net host -v ${WORKING_DIR}:/etc/haproxy/:z --entrypoint bash --name extlb quay.io/openshift/origin-haproxy-router  -c 'haproxy -f /etc/haproxy/haproxy.cfg'

    # update api and add api-int and *.apps entries to baremetal network DNS
    # delete existing entries pointing to the wrong api ip before adding correct entry
    sudo virsh net-update ${BAREMETAL_NETWORK_NAME} delete dns-host "<host ip='${api_ip}'> <hostname>api</hostname> </host>"  --live --config
    sudo virsh net-update ${BAREMETAL_NETWORK_NAME} delete dns-host "<host ip='${api_ip}'> <hostname>virthost</hostname> </host>"  --live --config
    sudo virsh net-update ${BAREMETAL_NETWORK_NAME} add dns-host "<host ip='${load_balancer_ip}'> <hostname>api</hostname> <hostname>api-int</hostname> <hostname>*.apps</hostname> <hostname>virthost</hostname> </host>"  --live --config
  fi
}

# Change the domain manufacturer to ensure validations pass when using specific platforms
function set_device_mfg() {

    platform=${3}
    platformName=${4}

    tmpdomain=$(mktemp --tmpdir "virt-domain--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $tmpdomain"

    for (( n=0; n<${2}; n++ ))
    do
        name=${CLUSTER_NAME}_${1}_${n}
        sudo virsh dumpxml ${name} > ${tmpdomain}

        if [[ "${platform}" == "external" ]] && [[ "${platformName}" == "oci" ]]; then
          sed -i '/\/os>/a\
 <sysinfo type="smbios">\
   <system>\
     <entry name="manufacturer">OracleCloud.com</entry>\
     <entry name="product">OCI</entry>\
   </system>\
 </sysinfo>' ${tmpdomain}
        elif [[ "${platform}" == "vsphere" ]]; then
          sed -i '/\/os>/a\
 <sysinfo type="smbios">\
   <system>\
     <entry name="manufacturer">VMware, Inc.</entry>\
   </system>\
 </sysinfo>' ${tmpdomain}
        else
          echo "Invalid platform ${platform} for manufacturer override"
          exit 1
	fi

        sed -i '/\<os>/a\
 <smbios mode="sysinfo"/>' ${tmpdomain}
       sudo virsh define ${tmpdomain}
    done
}

function node_val() {
    local n
    local val

    n="$1"
    val="$2"

    jq -r ".nodes[${n}].${val}" $NODES_FILE
}

function get_nodes_bmc_info() {

    AGENT_NODES_BMC_USERNAMES=()
    AGENT_NODES_BMC_PASSWORDS=()
    AGENT_NODES_BMC_ADDRESSES=()

    number_nodes=$NUM_MASTERS+$NUM_WORKERS

    for (( i=0; i<${number_nodes}; i++ ))
    do
      AGENT_NODES_BMC_USERNAMES+=($(node_val ${i} "driver_info.username"))
      AGENT_NODES_BMC_PASSWORDS+=($(node_val ${i} "driver_info.password"))
      AGENT_NODES_BMC_ADDRESSES+=($(node_val ${i} "driver_info.address"))
    done

    if [ "$NODES_PLATFORM" = "libvirt" ]; then
      if ! is_running vbmc; then
        # Force remove the pid file before restarting because podman
        # has told us the process isn't there but sometimes when it
        # dies it leaves the file.
        sudo rm -f $WORKING_DIR/virtualbmc/vbmc/master.pid
        sudo podman run -d --net host --privileged --name vbmc \
             -v "$WORKING_DIR/virtualbmc/vbmc":/root/.vbmc -v "/root/.ssh":/root/ssh \
             "${VBMC_IMAGE}"
      fi

      if ! is_running sushy-tools; then
        sudo podman run -d --net host --privileged --name sushy-tools \
             -v "$WORKING_DIR/virtualbmc/sushy-tools":/root/sushy -v "/root/.ssh":/root/ssh \
             "${SUSHY_TOOLS_IMAGE}"
      fi
    fi

}

write_pull_secret

# needed for assisted-service to run nmstatectl
# This is temporary and will go away when https://github.com/nmstate/nmstate is used
sudo yum install -y nmstate

get_static_ips_and_macs

get_nodes_bmc_info

if [[ ! -z "${MIRROR_IMAGES}" && "${MIRROR_IMAGES,,}" != "false" ]]; then
    if [[ ${MIRROR_COMMAND} == "oc-mirror" ]] && [[ ${AGENT_DEPLOY_MCE} == "true" ]]; then
        oc_mirror_mce
    fi
fi

if [[ "${NUM_MASTERS}" > "1" ]]; then
  if [[ "${AGENT_PLATFORM_TYPE}" == "none" || "${AGENT_PLATFORM_TYPE}" == "external" ]]; then
    # for platform "none" or "external" both API and INGRESS point to the same
    # load balancer IP address
    get_vips
    configure_dnsmasq ${PROVISIONING_HOST_EXTERNAL_IP} ${PROVISIONING_HOST_EXTERNAL_IP}
    enable_load_balancer ${API_VIPS} ${PROVISIONING_HOST_EXTERNAL_IP}
  else
    set_api_and_ingress_vip
  fi
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

if [[ "${AGENT_PLATFORM_TYPE}" == "external" ]] || [[ "${AGENT_PLATFORM_TYPE}" == "vsphere" ]]; then
  set_device_mfg master $NUM_MASTERS ${AGENT_PLATFORM_TYPE} ${AGENT_PLATFORM_NAME}
  set_device_mfg worker $NUM_WORKERS ${AGENT_PLATFORM_TYPE} ${AGENT_PLATFORM_NAME}
fi

generate_cluster_manifests

generate_extra_cluster_manifests
