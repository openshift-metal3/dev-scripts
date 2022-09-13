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

    # Set outside the range used for dhcp
    base_ip=80

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

function generate_cluster_manifests() {

  MANIFESTS_PATH="${OCP_DIR}/cluster-manifests"
  EXTRA_MANIFESTS_PATH="${OCP_DIR}/openshift"
  MIRROR_PATH="${OCP_DIR}/mirror"

  # Fetch current OpenShift version from the release payload
  VERSION="$(openshift_version ${OCP_DIR})"

  mkdir -p ${MANIFESTS_PATH}
  if [ ! -z "${MIRROR_IMAGES}" ]; then
    mkdir -p ${MIRROR_PATH}
  fi
  mkdir -p ${EXTRA_MANIFESTS_PATH}
  
  if [[ "$IP_STACK" = "v4" ]]; then
    CLUSTER_NETWORK=${CLUSTER_SUBNET_V4}
    SERVICE_NETWORK=${SERVICE_SUBNET_V4}
    CLUSTER_HOST_PREFIX=${CLUSTER_HOST_PREFIX_V4}
  elif [[ "$IP_STACK" = "v6" ]]; then
    CLUSTER_NETWORK=${CLUSTER_SUBNET_V6}
    SERVICE_NETWORK=${SERVICE_SUBNET_V6}
    CLUSTER_HOST_PREFIX=${CLUSTER_HOST_PREFIX_V6}
  fi

    cat > "${MANIFESTS_PATH}/agent-cluster-install.yaml" << EOF
apiVersion: extensions.hive.openshift.io/v1beta1
kind: AgentClusterInstall
metadata:
  name: test-agent-cluster-install
  namespace: cluster0
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
    - cidr: ${CLUSTER_NETWORK}
      hostPrefix: ${CLUSTER_HOST_PREFIX}
    serviceNetwork:
    - ${SERVICE_NETWORK}
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
  namespace: cluster0
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

    local releaseImage=${OPENSHIFT_RELEASE_IMAGE}
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        releaseImage="${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}"
    # If not installing from src, let's use the current version from the binary
    elif [ -z "$KNI_INSTALL_FROM_GIT" ]; then
      local openshift_install="$(realpath "${OCP_DIR}/openshift-install")"
      releaseImage=$("${openshift_install}" --dir="${OCP_DIR}" version | grep "release image" | cut -d " " -f 3)
      echo "Setting release image to ${releaseImage}"
    fi

    cat > "${MANIFESTS_PATH}/cluster-image-set.yaml" << EOF
apiVersion: hive.openshift.io/v1
kind: ClusterImageSet
metadata:
  name: openshift-${VERSION}
spec:
  releaseImage: $releaseImage
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
  namespace: cluster0
spec:
  clusterRef:
    name: ${CLUSTER_NAME}
    namespace: cluster0
  pullSecretRef:
    name: pull-secret
  sshAuthorizedKey: ${SSH_PUB_KEY}
  nmStateConfigLabelSelector:
    matchLabels:
      cluster0-nmstate-label-name: cluster0-nmstate-label-value
EOF

    set +x
    pull_secret=$(cat $PULL_SECRET_FILE)
    cat > "${MANIFESTS_PATH}/pull-secret.yaml" << EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/dockerconfigjson
metadata:
  name: pull-secret
  namespace: cluster0
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
    cluster0-nmstate-label-name: cluster0-nmstate-label-value
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
              prefix-length: ${CLUSTER_HOST_PREFIX}
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

 cat > "${EXTRA_MANIFESTS_PATH}/agent-test.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: agent-test
  namespace: openshift-config
data:
  value: agent-test
EOF

    done

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

generate_cluster_manifests
