#!/bin/bash

set -euxo pipefail

source logging.sh
source common.sh
source network.sh
source rhcos.sh
source release_info.sh
source utils.sh
source validation.sh
source prepare_images.sh

early_deploy_validation

# Account for differences in 1.* and 2.* version reporting.
# shellcheck disable=SC2034
PODMAN_VERSION=$(sudo podman version -f json | jq -r '.Version,.Client.Version|strings')

prepare_images

for name in ironic ironic-api ironic-conductor ironic-inspector dnsmasq httpd-${PROVISIONING_NETWORK_NAME} mariadb; do
    sudo podman ps | grep -w " $name$" && sudo podman kill "$name"
    sudo podman ps --all | grep -w " $name$" && sudo podman rm "$name" -f
done

# Remove existing pod
if  sudo podman pod exists ironic-pod ; then
    sudo podman pod rm ironic-pod -f
fi

# Create pod
sudo podman pod create -n ironic-pod

IRONIC_IMAGE=${IRONIC_LOCAL_IMAGE:-$IRONIC_IMAGE}

for IMAGE in ${IRONIC_IMAGE} ${VBMC_IMAGE} ${SUSHY_TOOLS_IMAGE} ; do
    sudo -E podman pull --authfile "$PULL_SECRET_FILE" "$IMAGE" || echo "WARNING: Could not pull latest $IMAGE; will try to use cached images instead"
done

CACHED_MACHINE_OS_BOOTSTRAP_IMAGE="${IRONIC_DATA_DIR}/html/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}"
if [ ! -f "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" ]; then
  curl -g --insecure -L -o "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" "${MACHINE_OS_BOOTSTRAP_IMAGE_URL}"
  pushd "$(dirname "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}")"
  echo "${MACHINE_OS_BOOTSTRAP_IMAGE_SHA256} $(basename "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}")" | tee "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}.sha256sum"
  sha256sum --strict --check "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}.sha256sum" || ( rm -f "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" ; exit 1 )
  popd
fi

# cached images to the bootstrap VM
sudo -E podman pull --authfile "${PULL_SECRET_FILE}" "${IRONIC_IMAGE}" || echo "WARNING: Could not pull latest $IRONIC_IMAGE; will try to use cached images instead"
sudo podman run -d --net host --name "httpd-${PROVISIONING_NETWORK_NAME}" --pod ironic-pod \
     --env PROVISIONING_INTERFACE="${PROVISIONING_NETWORK_NAME}" \
     -v "$IRONIC_DATA_DIR:/shared" --security-opt label=disable \
     --entrypoint /bin/runhttpd "${IRONIC_IMAGE}"

if [ "$NODES_PLATFORM" = "libvirt" ]; then
    if ! is_running vbmc; then
        # Force remove the pid file before restarting because podman
        # has told us the process isn't there but sometimes when it
        # dies it leaves the file.
        sudo rm -f "$WORKING_DIR/virtualbmc/vbmc/master.pid"
        sudo podman run -d --net host --name vbmc --pod ironic-pod \
             -v "$WORKING_DIR/virtualbmc/vbmc":/root/.vbmc \
             -v /root/.ssh/id_rsa_virt_power:/root/ssh/id_rsa_virt_power:ro \
             -v /root/.ssh/id_rsa_virt_power.pub:/root/ssh/id_rsa_virt_power.pub:ro \
             -v /var/run/libvirt:/var/run/libvirt \
             --security-opt label=disable \
             "${VBMC_IMAGE}"
    fi

    if ! is_running sushy-tools; then
        sudo podman run -d --net host --name sushy-tools --pod ironic-pod \
             -v "$WORKING_DIR/virtualbmc/sushy-tools":/root/sushy \
             -v /root/.ssh/id_rsa_virt_power:/root/ssh/id_rsa_virt_power:ro \
             -v /root/.ssh/id_rsa_virt_power.pub:/root/ssh/id_rsa_virt_power.pub:ro \
             -v /var/run/libvirt:/var/run/libvirt \
             --security-opt label=disable \
             "${SUSHY_TOOLS_IMAGE}"
    fi
fi



# Wait for images to be downloaded/ready
while ! curl --fail -g "http://$(wrap_if_ipv6 "${PROVISIONING_HOST_IP}")/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}.sha256sum" ; do sleep 1 ; done
