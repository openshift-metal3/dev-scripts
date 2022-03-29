#!/usr/bin/env bash
set -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh

### Recommended configuration (compact scenario):
### export IP_STACK=v4
### export NETWORK_TYPE=OpenShiftSDN
### export NUM_WORKERS=0
### export MASTER_DISK=120
### export MASTER_MEMORY=16384

early_deploy_validation

export FLEETING_PATH=${FLEETING_PATH:-$WORKING_DIR/fleeting}
export FLEETING_ISO=${FLEETING_ISO:-$FLEETING_PATH/output/fleeting.iso}

node0=${CLUSTER_NAME}_master_0
node0_ip=$(nth_ip $EXTERNAL_SUBNET_V4 20)

function generate_fleeting_manifests() {

    FLEETING_MANIFESTS_PATH="${FLEETING_PATH}/manifests"

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
  apiVIP: 192.168.111.10
  ingressVIP: 192.168.111.11
  clusterDeploymentRef:
    name: compact-cluster
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
  sshPublicKey: ${SSH_PUB_KEY}
EOF

    cat > "${FLEETING_MANIFESTS_PATH}/cluster-deployment.yaml" << EOF
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: compact-cluster
  namespace: cluster0
spec:
  baseDomain: agent.example.com
  clusterInstallRef:
    group: extensions.hive.openshift.io
    kind: AgentClusterInstall
    name: test-agent-cluster-install
    version: v1beta1
  clusterName: compact-cluster
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
    name: compact-cluster  
    namespace: cluster0
  pullSecretRef:
    name: pull-secret
  sshAuthorizedKey: ${SSH_PUB_KEY}
  ignitionConfigOverride: '{"ignition": {"version": "3.1.0"}, "storage": {"files": [{"path": "/etc/someconfig", "contents": {"source": "data:text/plain;base64,aGVscGltdHJhcHBlZGluYXN3YWdnZXJzcGVj"}}]}}'
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
    set -x
}

function generate_fleeting_iso() {
    export REPO_PATH=${WORKING_DIR}
    sync_repo_and_patch fleeting https://github.com/openshift-agent-team/fleeting

    # If set, use the configured fleeting PR
    if [[ -n ${FLEETING_PR:-} ]]; then
      pushd ${FLEETING_PATH}
      git fetch origin pull/${FLEETING_PR}/head:pr${FLEETING_PR}
      git checkout pr${FLEETING_PR}
      popd
    fi

    generate_fleeting_manifests ${FLEETING_PATH}
    
    pushd ${FLEETING_PATH}
    export NODE_ZERO_IP=$1
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
generate_fleeting_iso ${node0_ip}

attach_fleeting_iso master $NUM_MASTERS
attach_fleeting_iso worker $NUM_WORKERS


