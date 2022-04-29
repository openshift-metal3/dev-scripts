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

early_deploy_validation

function get_static_ips_and_macs() {

    FLEETING_NODES_IPS=()
    FLEETING_NODES_MACS=()
    FLEETING_NODES_HOSTNAMES=()

    if [[ "$FLEETING_STATIC_IP_NODE0_ONLY" = "true" ]]; then
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
        FLEETING_NODES_IPS+=($(nth_ip ${external_subnet} ${ip}))

        if [[ $i < $NUM_MASTERS ]]; then
            FLEETING_NODES_HOSTNAMES+=($(printf ${MASTER_HOSTNAME_FORMAT} ${i}))
            cluster_name=${CLUSTER_NAME}_master_${i}
        else
	    worker_num=$((${i}-$NUM_MASTERS))
            FLEETING_NODES_HOSTNAMES+=($(printf ${WORKER_HOSTNAME_FORMAT} ${worker_num}))
            cluster_name=${CLUSTER_NAME}_worker_${worker_num}
        fi

        # Add a DNS entry for this hostname
        sudo virsh net-update ${BAREMETAL_NETWORK_NAME} add dns-host  "<host ip='${FLEETING_NODES_IPS[i]}'> <hostname>${FLEETING_NODES_HOSTNAMES[i]}</hostname> </host>"  --live --config

        # Get the generated mac addresses
        FLEETING_NODES_MACS+=($(sudo virsh dumpxml $cluster_name | xmllint --xpath "string(//interface[descendant::source[@bridge = '${BAREMETAL_NETWORK_NAME}']]/mac/@address)" -))
    done
}

function generate_fleeting_manifests() {

    mkdir -p ${FLEETING_MANIFESTS_PATH}

    if [[ "$IP_STACK" = "v4" ]]; then
      CLUSTER_NETWORK=${CLUSTER_SUBNET_V4}
      SERVICE_NETWORK=${SERVICE_SUBNET_V4}
      CLUSTER_HOST_PREFIX=${CLUSTER_HOST_PREFIX_V4}
    elif [[ "$IP_STACK" = "v6" ]]; then
      CLUSTER_NETWORK=${CLUSTER_SUBNET_V6}
      SERVICE_NETWORK=${SERVICE_SUBNET_V6}
      CLUSTER_HOST_PREFIX=${CLUSTER_HOST_PREFIX_V6}
    fi

    cat > "${FLEETING_MANIFESTS_PATH}/agent-cluster-install.yaml" << EOF
apiVersion: extensions.hive.openshift.io/v1beta1
kind: AgentClusterInstall
metadata:
  name: test-agent-cluster-install
  namespace: cluster0
spec:
  apiVIP: ${API_VIP}
  ingressVIP: ${INGRESS_VIP}
  clusterDeploymentRef:
    name: ${CLUSTER_NAME}
  imageSetRef:
    name: openshift-v4.10.0
  networking:
    clusterNetwork:
    - cidr: ${CLUSTER_NETWORK}
      hostPrefix: ${CLUSTER_HOST_PREFIX}
    serviceNetwork:
    - ${SERVICE_NETWORK}
  provisionRequirements:
    controlPlaneAgents: ${NUM_MASTERS}
    workerAgents: ${NUM_WORKERS}
  sshPublicKey: ${SSH_PUB_KEY}
EOF

    cat > "${FLEETING_MANIFESTS_PATH}/cluster-deployment.yaml" << EOF
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
  controlPlaneConfig:
    servingCertificates: {}
  platform:
    agentBareMetal:
      agentSelector:
        matchLabels:
          bla: aaa
  pullSecretRef:
    name: pull-secret
EOF

    cat > "${FLEETING_MANIFESTS_PATH}/infraenv.yaml" << EOF
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
    cat > "${FLEETING_MANIFESTS_PATH}/pull-secret.yaml" << EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/dockerconfigjson
metadata:
  name: pull-secret
  namespace: cluster0
stringData:
  .dockerconfigjson: '${pull_secret}'

EOF

    num_ips=${#FLEETING_NODES_IPS[@]}

    # Create a yaml for each host in nmstateconfig.yaml
    for (( i=0; i<$num_ips; i++ ))
    do
        cat >> "${FLEETING_MANIFESTS_PATH}/nmstateconfig.yaml" << EOF
apiVersion: agent-install.openshift.io/v1beta1
kind: NMStateConfig
metadata:
  name: ${FLEETING_NODES_HOSTNAMES[i]}
  namespace: openshift-machine-api
  labels:
    cluster0-nmstate-label-name: cluster0-nmstate-label-value
spec:
  config:
    interfaces:
      - name: eth0
        type: ethernet
        state: up
        mac-address: ${FLEETING_NODES_MACS[i]}
        ipv4:
          enabled: true
          address:
            - ip: ${FLEETING_NODES_IPS[i]}
              prefix-length: ${CLUSTER_HOST_PREFIX}
          dhcp: false
    dns-resolver:
      config:
        server:
          - ${PROVISIONING_HOST_EXTERNAL_IP}
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: ${PROVISIONING_HOST_EXTERNAL_IP}
          next-hop-interface: eth0
          table-id: 254
  interfaces:
    - name: "eth0"
      macAddress: ${FLEETING_NODES_MACS[i]}
---
EOF
    done

    set -x
}

function generate_fleeting_iso() {
    export REPO_PATH=${WORKING_DIR}

    sync_repo_and_patch fleeting https://github.com/openshift-agent-team/fleeting ${FLEETING_PR}

    generate_fleeting_manifests

    pushd ${FLEETING_PATH}
    make iso 
    popd
}

function attach_fleeting_iso() {
    for (( n=0; n<${2}; n++ ))
    do
        name=${CLUSTER_NAME}_${1}_${n}
        sudo virt-xml ${name} --add-device --disk ${FLEETING_ISO},device=cdrom,target.dev=sdc
        sudo virt-xml ${name} --edit target=sda --disk="boot_order=1"
        sudo virt-xml ${name} --edit target=sdc --disk="boot_order=2" --start
    done
}

write_pull_secret

# needed for assisted-service to run nmstatectl
# This is temporary and will go away when https://github.com/nmstate/nmstate is used
sudo yum install -y nmstate

get_static_ips_and_macs

set_api_and_ingress_vip

generate_fleeting_iso

attach_fleeting_iso master $NUM_MASTERS
attach_fleeting_iso worker $NUM_WORKERS


