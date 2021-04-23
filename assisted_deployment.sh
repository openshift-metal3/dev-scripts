#!/usr/bin/env bash
set -o pipefail

source logging.sh
source utils.sh
source common.sh


# Default values are managed through the operator itself.
# The defaults are not being set here on purpose so that the
# default operator flow can be used instead.
ASSISTED_SERVICE_IMAGE="${ASSISTED_SERVICE_IMAGE:-}"
ASSISTED_INSTALLER_IMAGE="${ASSISTED_INSTALLER_IMAGE:-}"
ASSISTED_AGENT_IMAGE="${ASSISTED_AGENT_IMAGE:-}"
ASSISTED_DATABASE_IMAGE="${ASSISTED_DATABASE_IMAGE:-}"
ASSISTED_CONTROLLER_IMAGE="${ASSISTED_CONTROLLER_IMAGE:-}"
ASSISTED_OPENSHIFT_VERSIONS="${ASSISTED_OPENSHIFT_VERSIONS:-}"

ASSISTED_NAMESPACE="${ASSISTED_NAMESPACE:-assisted-installer}"
ASSISTED_OPERATOR_INDEX="${ASSISTED_OPERATOR_INDEX:-quay.io/ocpmetal/assisted-service-index:latest}"


function deploy_local_storage() {
  oc adm new-project openshift-local-storage || true

  oc annotate project openshift-local-storage openshift.io/node-selector=''

  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: local-operator-group
  namespace: openshift-local-storage
spec:
  targetNamespaces:
    - openshift-local-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: local-storage-operator
  namespace: openshift-local-storage
spec:
  installPlanApproval: Automatic
  name: local-storage-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

  wait_for_crd "localvolumes.local.storage.openshift.io"

  echo "Creating local volume and storage class..."
  cat <<EOCR | oc apply -f -
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: assisted-service
  namespace: openshift-local-storage
spec:
  logLevel: Normal
  managementState: Managed
  storageClassDevices:
    - devicePaths:
        - /dev/sdb
        - /dev/sdc
      storageClassName: assisted-service
      volumeMode: Filesystem
EOCR
}


function deploy_hive() {
  echo "Installing Hive..."

  cat <<EOCR | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hive-operator
  namespace: openshift-operators
spec:
  installPlanApproval: Automatic
  name: hive-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
EOCR

  wait_for_crd "clusterdeployments.hive.openshift.io"
}


function subscription_config() {
    if [ -n "${ASSISTED_SERVICE_IMAGE}" ]; then
cat <<EOF
    - name: SERVICE_IMAGE
      value: '$ASSISTED_SERVICE_IMAGE'
EOF
    fi

    if [ -n "${ASSISTED_INSTALLER_IMAGE}" ]; then
cat <<EOF
    - name: INSTALLER_IMAGE
      value: '$ASSISTED_INSTALLER_IMAGE'
EOF
    fi

    if [ -n "${ASSISTED_AGENT_IMAGE}" ]; then
cat <<EOF
    - name: AGENT_IMAGE
      value: '$ASSISTED_AGENT_IMAGE'
EOF
    fi

    if [ -n "${ASSISTED_DATABASE_IMAGE}" ]; then
cat <<EOF
    - name: DATABASE_IMAGE
      value: '$ASSISTED_DATABASE_IMAGE'
EOF
    fi

    if [ -n "${ASSISTED_CONTROLLER_IMAGE}" ]; then
cat <<EOF
    - name: CONTROLLER_IMAGE
      value: '$ASSISTED_CONTROLLER_IMAGE'
EOF
    fi

    if [ -n "${ASSISTED_OPENSHIFT_VERSIONS}" ]; then
cat <<EOF
    - name: OPENSHIFT_VERSIONS
      value: '$ASSISTED_OPENSHIFT_VERSIONS'
EOF
    fi
}


function deploy_assisted_operator() {
  echo "Installing assisted-installer operator..."

  cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $ASSISTED_NAMESPACE
  labels:
    name: $ASSISTED_NAMESPACE
EOF

  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: assisted-service-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: $ASSISTED_OPERATOR_INDEX
EOF

  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
    name: assisted-installer-group
    namespace: $ASSISTED_NAMESPACE
spec:
  targetNamespaces:
    - $ASSISTED_NAMESPACE
EOF

  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: assisted-service-operator
  namespace: $ASSISTED_NAMESPACE
spec:
  config:
    env:
$(subscription_config)
  installPlanApproval: Automatic
  name: assisted-service-operator
  source: assisted-service-catalog
  sourceNamespace: openshift-marketplace
  startingCSV: assisted-service-operator.v0.0.1
EOF

  wait_for_crd "agentserviceconfigs.agent-install.openshift.io"

  cat <<EOF | oc apply -f -
apiVersion: agent-install.openshift.io/v1beta1
kind: AgentServiceConfig
metadata:
 namespace: $ASSISTED_NAMESPACE
 name: agent
spec:
 databaseStorage:
  storageClassName: assisted-service
  accessModes:
  - ReadWriteOnce
  resources:
   requests:
    storage: 8Gi
 filesystemStorage:
  storageClassName: assisted-service
  accessModes:
  - ReadWriteOnce
  resources:
   requests:
    storage: 8Gi
EOF

}

function install_assisted_service() {
 # Verify extra disks were created for the nodes
 deploy_local_storage
 deploy_hive
 deploy_assisted_operator

 oc wait -n "$ASSISTED_NAMESPACE" --for=condition=Ready pod -l app=assisted-service --timeout=90s
}

function delete_assisted() {
    oc delete -n $ASSISTED_NAMESPACE agentserviceconfig agent
    oc delete -n $ASSISTED_NAMESPACE csv assisted-service-operator.v0.0.1
    oc delete subscription -n $ASSISTED_NAMESPACE assisted-service-operator
    oc delete -n $ASSISTED_NAMESPACE operatorgroup assisted-installer-group
    oc delete -n openshift-marketplace catalogsource assisted-service-catalog
    oc delete ns $ASSISTED_NAMESPACE
}

function delete_hive() {
  oc delete subscription -n openshift-operators hive-operator
}

function delete_all() {
    if  [ "$NODES_PLATFORM" = "assisted" ]; then
        delete_assisted
        delete_hive
    fi

    # Skipping LocalVolume cleanup on purpose.
}

"$@"
