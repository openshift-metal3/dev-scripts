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

early_deploy_validation

CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE:-"cluster0"}

function get_static_ips_and_macs() {

    AGENT_NODES_IPS=()
    AGENT_NODES_MACS=()
    AGENT_NODES_HOSTNAMES=()

    if [[ "$AGENT_STATIC_IP_NODE0_ONLY" = "true" ]]; then
        static_ips=1
    else
        static_ips=$NUM_MASTERS+$NUM_WORKERS
    fi

    if [[ "$IP_STACK" = "v4" ]]; then
        external_subnet=$EXTERNAL_SUBNET_V4
    else
        external_subnet=$EXTERNAL_SUBNET_V6
    fi

    if [[ $NETWORKING_MODE == "DHCP" ]]; then
      base_ip=20
    else
      # Set outside the range used for dhcp
      base_ip=80
    fi

    for (( i=0; i<${static_ips}; i++ ))
    do
        ip=${base_ip}+${i}
        AGENT_NODES_IPS+=($(nth_ip ${external_subnet} ${ip}))

        if [[ $i < $NUM_MASTERS ]]; then
            AGENT_NODES_HOSTNAMES+=($(printf ${MASTER_HOSTNAME_FORMAT} ${i}))
            cluster_name=${CLUSTER_NAME}_master_${i}
        else
	    worker_num=$((${i}-$NUM_MASTERS))
            AGENT_NODES_HOSTNAMES+=($(printf ${WORKER_HOSTNAME_FORMAT} ${worker_num}))
            cluster_name=${CLUSTER_NAME}_worker_${worker_num}
        fi

        # Add a DNS entry for this hostname if it's not already defined
        if ! $(sudo virsh net-dumpxml ${BAREMETAL_NETWORK_NAME} | xmllint --xpath "//dns/host[@ip = '${AGENT_NODES_IPS[i]}']" - &> /dev/null); then
          sudo virsh net-update ${BAREMETAL_NETWORK_NAME} add dns-host  "<host ip='${AGENT_NODES_IPS[i]}'> <hostname>${AGENT_NODES_HOSTNAMES[i]}</hostname> </host>"  --live --config
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
    networkType: ${NETWORK_TYPE}
  provisionRequirements:
    controlPlaneAgents: ${NUM_MASTERS}
    workerAgents: ${NUM_WORKERS}
  sshPublicKey: ${SSH_PUB_KEY}
EOF

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

if [ ! -z "${MIRROR_IMAGES}" ]; then
# TODO - get the mirror registry info from output of 'oc adm release mirror'

    cat > "${MIRROR_PATH}/registries.conf" << EOF
[[registry]]
prefix = ""
location = "registry.ci.openshift.org/ocp/release"
mirror-by-digest-only = false

[[registry.mirror]]
location = "${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image"

[[registry]]
prefix = ""
location = "quay.io/openshift-release-dev/ocp-v4.0-art-dev"
mirror-by-digest-only = false

[[registry.mirror]]
location = "${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image"
EOF

cp $REGISTRY_DIR/certs/$REGISTRY_CRT ${MIRROR_PATH}/ca-bundle.crt

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

    num_ips=${#AGENT_NODES_IPS[@]}

    if [[ "$IP_STACK" = "v4" ]]; then
       interface_type="ipv4"
       route_dest="0.0.0.0/0"
    else
       interface_type="ipv6"
       route_dest="::/0"
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
        ${interface_type}:
          enabled: true
          address:
            - ip: ${AGENT_NODES_IPS[i]}
              prefix-length: ${cluster_host_prefix}
          dhcp: false
    dns-resolver:
      config:
        server:
          - ${PROVISIONING_HOST_EXTERNAL_IP}
    routes:
      config:
        - destination: ${route_dest}
          next-hop-address: ${PROVISIONING_HOST_EXTERNAL_IP}
          next-hop-interface: eth0
          table-id: 254
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

function generate_install_config_agent_config() {

  MANIFESTS_PATH="${OCP_DIR}"
  mkdir -p ${MANIFESTS_PATH}
  
  setNetworkingVars

    cat > "${MANIFESTS_PATH}/agent-config.yaml" << EOF
apiVersion: v1alpha1
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${CLUSTER_NAMESPACE}
rendezvousIP: ${AGENT_NODES_IPS[0]}
EOF
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
  networkType: OpenShiftSDN
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

write_pull_secret

# needed for assisted-service to run nmstatectl
# This is temporary and will go away when https://github.com/nmstate/nmstate is used
sudo yum install -y nmstate

get_static_ips_and_macs


if [ ! -z "${MIRROR_IMAGES}" ]; then

  setup_local_registry

  setup_release_mirror

fi

 if [[ "${NUM_MASTERS}" > "1" ]]; then
    set_api_and_ingress_vip
  fi

if [[ $NETWORKING_MODE == "DHCP" ]]; then
  generate_install_config_agent_config
else
  generate_cluster_manifests
fi

generate_extra_cluster_manifests
