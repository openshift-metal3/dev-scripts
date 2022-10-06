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

CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE:-"cluster0"}

function get_nmstate_interface_block {

index="$1"

if [[ "$IP_STACK" = "v4" ]]; then
  echo "ipv4:
          enabled: true
          address:
            - ip: ${AGENT_NODES_IPS[index]}
              prefix-length: ${CLUSTER_HOST_PREFIX_V4}
          dhcp: false"
elif [[ "$IP_STACK" = "v6" ]]; then
  echo "ipv6:
          enabled: true
          address:
            - ip: ${AGENT_NODES_IPSV6[index]}
              prefix-length: ${CLUSTER_HOST_PREFIX_V6}
          dhcp: false"
else
       # v4v6
  echo "ipv4:
          enabled: true
          address:
            - ip: ${AGENT_NODES_IPS[index]}
              prefix-length: ${CLUSTER_HOST_PREFIX_V4}
          dhcp: false
        ipv6:
          enabled: true
          address:
            - ip: ${AGENT_NODES_IPSV6[index]}
              prefix-length: ${CLUSTER_HOST_PREFIX_V6}
          dhcp: false"
fi

}

function get_nmstate_dns_block {

if [[ "$IP_STACK" != "v4v6" ]]; then
  echo "server:
          - ${PROVISIONING_HOST_EXTERNAL_IP}"

else
  provisioning_host_external_ipv6=$(nth_ip $EXTERNAL_SUBNET_V6 1)
  echo "server:
          - ${PROVISIONING_HOST_EXTERNAL_IP}
          - ${provisioning_host_external_ipv6}"
fi

}

function get_nmstate_route_block {

if [[ "$IP_STACK" = "v4" ]]; then
  echo "- destination: 0.0.0.0/0
          next-hop-address: ${PROVISIONING_HOST_EXTERNAL_IP}
          next-hop-interface: eth0
          table-id: 254"
elif [[ "$IP_STACK" = "v6" ]]; then
  echo "- destination: ::/0
          next-hop-address: ${PROVISIONING_HOST_EXTERNAL_IP}
          next-hop-interface: eth0
          table-id: 254"
else
  provisioning_host_external_ipv6=$(nth_ip $EXTERNAL_SUBNET_V6 1)
  echo "- destination: 0.0.0.0/0
          next-hop-address: ${PROVISIONING_HOST_EXTERNAL_IP}
          next-hop-interface: eth0
          table-id: 254
        - destination: ::/0
          next-hop-address: ${provisioning_host_external_ipv6}
          next-hop-interface: eth0
          table-id: 254"
fi

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
        elif [[ "$IP_STACK" = "v6" ]]; then
            AGENT_NODES_IPSV6+=($(nth_ip ${EXTERNAL_SUBNET_V6} ${ip}))
	    add_dns_entry ${AGENT_NODES_IPSV6[i]} ${AGENT_NODES_HOSTNAMES[i]}
        else
	    # v4v6
            AGENT_NODES_IPS+=($(nth_ip ${EXTERNAL_SUBNET_V4} ${ip}))
            AGENT_NODES_IPSV6+=($(nth_ip $EXTERNAL_SUBNET_V6 ${ip}))
	    add_dns_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
	    add_dns_entry ${AGENT_NODES_IPSV6[i]} ${AGENT_NODES_HOSTNAMES[i]}
        fi

        # Get the generated mac addresses
        AGENT_NODES_MACS+=($(sudo virsh dumpxml $cluster_name | xmllint --xpath "string(//interface[descendant::source[@bridge = '${BAREMETAL_NETWORK_NAME}']]/mac/@address)" -))
    done
}

function setNetworkingVars() {
   if [[ "$IP_STACK" = "v4" ]]; then
    cluster_network=${CLUSTER_SUBNET_V4}
    service_network=${SERVICE_SUBNET_V4}
    machine_network=${EXTERNAL_SUBNET_V4}
    cluster_host_prefix=${CLUSTER_HOST_PREFIX_V4}
  elif [[ "$IP_STACK" = "v6" ]]; then
    cluster_network=${CLUSTER_SUBNET_V6}
    service_network=${SERVICE_SUBNET_V6}
    machine_network=${EXTERNAL_SUBNET_V6}
    cluster_host_prefix=${CLUSTER_HOST_PREFIX_V6}
  fi
}

function generate_cluster_manifests() {

  MANIFESTS_PATH="${OCP_DIR}/cluster-manifests"
  MIRROR_PATH="${OCP_DIR}/mirror"

  # Fetch current OpenShift version from the release payload
  VERSION="$(openshift_version ${OCP_DIR})"

  mkdir -p ${MANIFESTS_PATH}
  if [ ! -z "${MIRROR_IMAGES}" ]; then
    mkdir -p ${MIRROR_PATH}
  fi

  setNetworkingVars

    cat > "${MANIFESTS_PATH}/agent-cluster-install.yaml" << EOF
apiVersion: extensions.hive.openshift.io/v1beta1
kind: AgentClusterInstall
metadata:
  name: test-agent-cluster-install
  namespace: ${CLUSTER_NAMESPACE}
spec:
EOF
if [[ "${NUM_MASTERS}" > "1" ]]; then
cat >> "${MANIFESTS_PATH}/agent-cluster-install.yaml" << EOF
  apiVIP: ${API_VIP}
  ingressVIP: ${INGRESS_VIP}
EOF
fi

if [[ "$IP_STACK" != "v4v6" ]]; then
cat >> "${MANIFESTS_PATH}/agent-cluster-install.yaml" << EOF
  clusterDeploymentRef:
    name: ${CLUSTER_NAME}
  imageSetRef:
    name: openshift-${VERSION}
  networking:
    clusterNetwork:
    - cidr: ${cluster_network}
      hostPrefix: ${cluster_host_prefix}
    serviceNetwork:
    - ${service_network}
    machineNetwork:
    - cidr: ${machine_network}
    networkType: ${NETWORK_TYPE}
  provisionRequirements:
    controlPlaneAgents: ${NUM_MASTERS}
    workerAgents: ${NUM_WORKERS}
  sshPublicKey: ${SSH_PUB_KEY}
EOF
else
cat >> "${MANIFESTS_PATH}/agent-cluster-install.yaml" << EOF
  clusterDeploymentRef:
    name: ${CLUSTER_NAME}
  imageSetRef:
    name: openshift-${VERSION}
  networking:
    clusterNetwork:
    - cidr: ${CLUSTER_SUBNET_V4}
      hostPrefix: ${CLUSTER_HOST_PREFIX_V4}
    - cidr: ${CLUSTER_SUBNET_V6}
      hostPrefix: ${CLUSTER_HOST_PREFIX_V6}
    serviceNetwork:
    - ${SERVICE_SUBNET_V4}
    - ${SERVICE_SUBNET_V6}
    machineNetwork:
    - cidr: ${EXTERNAL_SUBNET_V4}
    - cidr: ${EXTERNAL_SUBNET_V6}
    networkType: ${NETWORK_TYPE}
  provisionRequirements:
    controlPlaneAgents: ${NUM_MASTERS}
    workerAgents: ${NUM_WORKERS}
  sshPublicKey: ${SSH_PUB_KEY}
EOF
fi

    cat > "${MANIFESTS_PATH}/cluster-deployment.yaml" << EOF
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${CLUSTER_NAMESPACE}
spec:
  baseDomain: ${BASE_DOMAIN}
  clusterInstallRef:
    group: extensions.hive.openshift.io
    kind: AgentClusterInstall
    name: test-agent-cluster-install
    version: v1beta1
  clusterName: ${CLUSTER_NAME}
  pullSecretRef:
    name: pull-secret
EOF

    cat > "${MANIFESTS_PATH}/cluster-image-set.yaml" << EOF
apiVersion: hive.openshift.io/v1
kind: ClusterImageSet
metadata:
  name: openshift-${VERSION}
spec:
  releaseImage: $(getReleaseImage)
EOF

if [[ ! -z "${MIRROR_IMAGES}" ]] || [[ ! -z "${OC_MIRROR}" ]]; then
   # Set up registries.conf and ca-bundle.crt for mirroring
  ansible-playbook "${SCRIPTDIR}/agent/assets/ztp/registries-conf-playbook.yaml" -e "mirror_path=${SCRIPTDIR}/${MIRROR_PATH}"

   # Store the certs for registry
   if [[ "${REGISTRY_BACKEND}" = "podman" ]]; then
      cp $REGISTRY_DIR/certs/$REGISTRY_CRT ${MIRROR_PATH}/ca-bundle.crt
   else
      cp ${WORKING_DIR}/quay-install/quay-rootCA/rootCA.pem ${MIRROR_PATH}/ca-bundle.crt
   fi
fi

    cat > "${MANIFESTS_PATH}/infraenv.yaml" << EOF
apiVersion: agent-install.openshift.io/v1beta1
kind: InfraEnv
metadata:
  name: myinfraenv
  namespace: ${CLUSTER_NAMESPACE}
spec:
  clusterRef:
    name: ${CLUSTER_NAME}
    namespace: ${CLUSTER_NAMESPACE}
  pullSecretRef:
    name: pull-secret
  sshAuthorizedKey: ${SSH_PUB_KEY}
  nmStateConfigLabelSelector:
    matchLabels:
      ${CLUSTER_NAMESPACE}-nmstate-label-name: ${CLUSTER_NAMESPACE}-nmstate-label-value
EOF

    set +x
    pull_secret=$(cat $PULL_SECRET_FILE)
    cat > "${MANIFESTS_PATH}/pull-secret.yaml" << EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/dockerconfigjson
metadata:
  name: pull-secret
  namespace: ${CLUSTER_NAMESPACE}
stringData:
  .dockerconfigjson: '${pull_secret}'

EOF

    if [[ "$IP_STACK" = "v4" ]]; then
       num_ips=${#AGENT_NODES_IPS[@]}
    else
       num_ips=${#AGENT_NODES_IPSV6[@]}
    fi

    # Create a yaml for each host in nmstateconfig.yaml
    for (( i=0; i<$num_ips; i++ ))
    do
        cat >> "${MANIFESTS_PATH}/nmstateconfig.yaml" << EOF
apiVersion: agent-install.openshift.io/v1beta1
kind: NMStateConfig
metadata:
  name: ${AGENT_NODES_HOSTNAMES[i]}
  namespace: openshift-machine-api
  labels:
    ${CLUSTER_NAMESPACE}-nmstate-label-name: ${CLUSTER_NAMESPACE}-nmstate-label-value
spec:
  config:
    interfaces:
      - name: eth0
        type: ethernet
        state: up
        mac-address: ${AGENT_NODES_MACS[i]}
        $(get_nmstate_interface_block i)
    dns-resolver:
      config:
        $(get_nmstate_dns_block)
    routes:
      config:
        $(get_nmstate_route_block)
  interfaces:
    - name: "eth0"
      macAddress: ${AGENT_NODES_MACS[i]}
---
EOF
    done

    set -x
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
    cp ${SCRIPTDIR}/agent/assets/mce/agent_mce_0_*.yaml ${EXTRA_MANIFESTS_PATH}
  fi
}

function generate_agent_config() {

  MANIFESTS_PATH="${OCP_DIR}"
  mkdir -p ${MANIFESTS_PATH}

    cat > "${MANIFESTS_PATH}/agent-config.yaml" << EOF
apiVersion: v1alpha1
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${CLUSTER_NAMESPACE}
rendezvousIP: ${AGENT_NODES_IPS[0]}
EOF
}

function generate_install_config() {

  MANIFESTS_PATH="${OCP_DIR}"
  mkdir -p ${MANIFESTS_PATH}

  setNetworkingVars

  set +x
  pull_secret=$(cat $PULL_SECRET_FILE)
    cat > "${MANIFESTS_PATH}/install-config.yaml" << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- hyperthreading: Enabled
  name: worker
  replicas: ${NUM_WORKERS}
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: ${NUM_MASTERS}
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${CLUSTER_NAMESPACE}
networking:
  clusterNetwork:
  - cidr: ${cluster_network}
    hostPrefix: ${cluster_host_prefix}
  networkType: ${NETWORK_TYPE}
  machineNetwork:
  - cidr: ${machine_network}
  serviceNetwork:
  - ${service_network}
platform:
EOF
# The assumption here is if number of masters is one
# we want to generate an install config for none platform
# to create a SNO cluster.
if [[ "${NUM_MASTERS}" == "1" ]]; then
cat >> "${MANIFESTS_PATH}/install-config.yaml" << EOF
  none: {}
EOF
else
cat >> "${MANIFESTS_PATH}/install-config.yaml" << EOF
    baremetal:
      apiVips:
        - ${API_VIP}
      ingressVips:
        - ${INGRESS_VIP}
      hosts:
EOF
 num_ips=${#AGENT_NODES_IPS[@]}
 for (( i=0; i<$num_ips; i++ ))
    do
      cat >> "${MANIFESTS_PATH}/install-config.yaml" << EOF
          - name: host${i}
            bootMACAddress: ${AGENT_NODES_MACS[i]}
EOF
    done
fi
cat >> "${MANIFESTS_PATH}/install-config.yaml" << EOF
fips: false
sshKey: ${SSH_PUB_KEY}
pullSecret:  '${pull_secret}'
EOF
    set -x
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

write_pull_secret

# needed for assisted-service to run nmstatectl
# This is temporary and will go away when https://github.com/nmstate/nmstate is used
sudo yum install -y nmstate

get_static_ips_and_macs


if [ ! -z "${MIRROR_IMAGES}" ]; then

     setup_local_registry

     setup_release_mirror

fi

if [  "${OC_MIRROR}" == "true " ] && [  "${AGENT_DEPLOY_MCE}" == "true " ]; then
  oc_mirror_mce
fi

 if [[ "${NUM_MASTERS}" > "1" ]]; then
    set_api_and_ingress_vip
  fi

if [[ $NETWORKING_MODE == "DHCP" ]]; then
  generate_agent_config
  generate_install_config
else
  generate_cluster_manifests
fi

generate_extra_cluster_manifests