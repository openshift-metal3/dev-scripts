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

ASSETS_DIR="${OCP_DIR}/saved-assets/assisted-installer-manifests"


function generate_local_storage() {
  cat >"${ASSETS_DIR}/01-local-storage-operator.yaml" <<EOF
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

  cat >"${ASSETS_DIR}/02-local-volume.yaml" <<EOCR
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: assisted-service
  namespace: openshift-local-storage
spec:
  logLevel: Normal
  managementState: Managed
  storageClassDevices:
$(storage_devices_config)
      storageClassName: assisted-service
      volumeMode: Filesystem
EOCR
}


function storage_devices_config() {
  if [ ! -z "${VM_EXTRADISKS_LIST}" ]; then
cat <<EOF
    - devicePaths:
EOF
  fi

  for disk in ${VM_EXTRADISKS_LIST}; do
cat <<EOF
        - /dev/$disk
EOF
  done
}


function deploy_local_storage() {
  oc adm new-project openshift-local-storage || true

  oc annotate project openshift-local-storage openshift.io/node-selector=''

  generate_local_storage

  echo "Creating local storage operator group and subscription..."
  oc apply -f "${ASSETS_DIR}/01-local-storage-operator.yaml"
  wait_for_crd "localvolumes.local.storage.openshift.io"

  echo "Creating local volume and storage class..."
  oc apply -f "${ASSETS_DIR}/02-local-volume.yaml"
}


function generate_hive() {
  cat >"${ASSETS_DIR}/03-hive.yaml" <<EOCR
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
}


function deploy_hive() {
  echo "Installing Hive..."

  generate_hive
  oc apply -f "${ASSETS_DIR}/03-hive.yaml"

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


function generate_assisted_operator() {
  cat >"${ASSETS_DIR}/04-assisted-service.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $ASSISTED_NAMESPACE
  labels:
    name: $ASSISTED_NAMESPACE
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: assisted-service-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: $ASSISTED_OPERATOR_INDEX
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
    name: assisted-installer-group
    namespace: $ASSISTED_NAMESPACE
spec:
  targetNamespaces:
    - $ASSISTED_NAMESPACE
---
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
EOF

  cat >"${ASSETS_DIR}/05-assisted-service-config.yaml" <<EOF
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


function deploy_assisted_operator() {
  echo "Installing assisted-installer operator..."

  generate_assisted_operator

  oc apply -f "${ASSETS_DIR}/04-assisted-service.yaml"
  wait_for_crd "agentserviceconfigs.agent-install.openshift.io"

  oc apply -f "${ASSETS_DIR}/05-assisted-service-config.yaml"
}


function patch_extra_host_manifests() {
  if [ -f "${OCP_DIR}/extra_host_manifests.yaml" ]; then
    cp "${OCP_DIR}/extra_host_manifests.yaml" "${ASSETS_DIR}/06-extra-host-manifests.yaml"

    yq -i -Y '. | select(."kind" == "BareMetalHost") | .metadata += {"namespace":'\"${ASSISTED_NAMESPACE}\"'}' "${ASSETS_DIR}/06-extra-host-manifests.yaml"
    yq -i -Y '. | select(."kind" == "BareMetalHost") | .metadata.labels += {"infraenvs.agent-install.openshift.io":"myinfraenv"}' "${ASSETS_DIR}/06-extra-host-manifests.yaml"
    yq -i -Y '. | select(."kind" == "BareMetalHost") | .metadata.annotations += {"inspect.metal3.io":"disabled"}' "${ASSETS_DIR}/06-extra-host-manifests.yaml"
    yq -i -Y '. | select(."kind" == "BareMetalHost") | .spec += {"automatedCleaningMode":"disabled"}' "${ASSETS_DIR}/06-extra-host-manifests.yaml"
    echo "---" >> "${ASSETS_DIR}/06-extra-host-manifests.yaml"
    yq -Y '. | select(."kind" == "Secret") | .metadata += {"namespace":'\"${ASSISTED_NAMESPACE}\"'}' "${OCP_DIR}/extra_host_manifests.yaml" >> "${ASSETS_DIR}/06-extra-host-manifests.yaml"
  fi
}

function install_assisted_service() {
 mkdir -p "${ASSETS_DIR}"
 patch_extra_host_manifests
 deploy_local_storage
 deploy_hive
 deploy_assisted_operator

 oc wait -n "$ASSISTED_NAMESPACE" --for=condition=Ready pod -l app=assisted-service --timeout=90s

 echo "Installation finished..."
 echo "For debugging purposes all the manifests have been saved in ${OCP_DIR}/saved-assets/assisted-installer-manifests"
 echo "Please remember to manually apply BareMetalHost manifest available in the directory above."
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
