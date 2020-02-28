#!/bin/bash

function release_image() {
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        echo "releaseImage: ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image"
    else
        echo "releaseImage: ${OPENSHIFT_RELEASE_IMAGE}"
    fi
}

function generate_hive_assets() {
    local outdir
    local hypervisor_host

    # The LIBVIRT_URI might have been overridden to not point to
    # PROVISIONING_HOST_IP, so extract the IP of the host we have in
    # the URI.
    hypervisor_host=$(python3 -c "import urllib.parse; print(urllib.parse.urlparse(\"$LIBVIRT_URI\").hostname)")

    outdir="$1"
    cat > "${outdir}/manifests.yaml" <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ${CLUSTER_NAME}-pull-secret
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |-
    $(echo $PULL_SECRET | jq -c .)

---
apiVersion: v1
kind: Secret
metadata:
  name: ${CLUSTER_NAME}-ssh-private-key
stringData:
  ssh-privatekey: |-
$(cat ${SSH_PRIVATE_KEY_NAME} | sed 's/^/    /g')

---
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: ${CLUSTER_NAME}
  annotations:
    # do not retry if first deploy fails
    hive.openshift.io/try-install-once: "true"
spec:
  baseDomain: ${BASE_DOMAIN}
  clusterName: ${CLUSTER_NAME}
  controlPlaneConfig:
    servingCertificates: {}
  platform:
    baremetal:
      libvirtSSHPrivateKeySecretRef:
        name: ${CLUSTER_NAME}-ssh-private-key
  provisioning:
    installConfigSecretRef:
      name: ${CLUSTER_NAME}-install-config
    sshPrivateKeySecretRef:
      name: ${CLUSTER_NAME}-ssh-private-key
    $(release_image)
    sshKnownHosts:
$(ssh-keyscan -H ${hypervisor_host} 2>/dev/null | sed -e 's/^/      - "/g' -e 's/$/"/g')
  pullSecretRef:
    name: ${CLUSTER_NAME}-pull-secret

EOF

    cat > "${outdir}/create.sh" <<EOF
#!/usr/bin/env bash

set -xe

bindir=\$(dirname \$0)

if [[ -z "\$KUBECONFIG" ]]; then
   echo "This script might fail because KUBECONFIG is not set."
fi

if ! (oc projects | grep -q ${CLUSTER_NAME}); then
   oc new-project ${CLUSTER_NAME}
fi

oc delete secret ${CLUSTER_NAME}-pull-secret || true
oc delete secret ${CLUSTER_NAME}-install-config || true

oc create secret generic -n ${CLUSTER_NAME} ${CLUSTER_NAME}-install-config --from-file=install-config.yaml=\${bindir}/install-config.yaml

oc delete -n ${CLUSTER_NAME} clusterdeployment ${CLUSTER_NAME} || true

oc apply -n ${CLUSTER_NAME} -f \${bindir}/manifests.yaml

EOF

    chmod +x "${outdir}/create.sh"

    local BOOTSTRAP_IP=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$PROVISIONING_NETWORK"', 2))")
    local CLUSTER_IP=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$PROVISIONING_NETWORK"', 3))")

    cat - >${outdir}/clouds.yaml <<EOF
clouds:
  metal3:
    auth_type: none
    baremetal_endpoint_override: http://$(wrap_if_ipv6 ${BOOTSTRAP_IP}):6385
    baremetal_introspection_endpoint_override: http://$(wrap_if_ipv6 ${BOOTSTRAP_IP}):5050
  metal3-bootstrap:
    auth_type: none
    baremetal_endpoint_override: http://$(wrap_if_ipv6 ${CLUSTER_IP}):6385
    baremetal_introspection_endpoint_override: http://$(wrap_if_ipv6 ${CLUSTER_IP}):5050
EOF
}
