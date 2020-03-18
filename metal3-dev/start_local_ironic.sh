#!/bin/bash

set -euxo pipefail

source $(dirname $(dirname $0))/logging.sh
source $(dirname $(dirname $0))/common.sh
source $(dirname $(dirname $0))/utils.sh

DHCP_RANGE_START=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$PROVISIONING_NETWORK"', 10))")
DHCP_RANGE_END=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$PROVISIONING_NETWORK"', 100))")
DHCP_RANGE=${DHCP_RANGE:-"${DHCP_RANGE_START}","${DHCP_RANGE_END}"}

# Add firewall rules to ensure the IPA ramdisk can reach Ironic and the Inspector API on the host

for port in 80 5050 6385 ; do
    if [ "${RHEL8}" = "True" ] || [ "${CENTOS8}" = "True" ]; then
        sudo firewall-cmd --zone=libvirt --add-port=${port}/tcp
        sudo firewall-cmd --zone=libvirt --add-port=${port}/tcp --permanent
    else
        if ! sudo iptables -C INPUT -i "${PROVISIONING_NETWORK_NAME}" -p tcp -m tcp --dport $port -j ACCEPT > /dev/null 2>&1; then
            sudo iptables -I INPUT -i "${PROVISIONING_NETWORK_NAME}" -p tcp -m tcp --dport $port -j ACCEPT
        fi
    fi
done

# Allow access to dhcp and tftp server for pxeboot
for port in 67 69 546 547; do
    if [ "${RHEL8}" = "True" ] || [ "${CENTOS8}" = "True" ]; then
        sudo firewall-cmd --zone=libvirt --add-port=${port}/udp
        sudo firewall-cmd --zone=libvirt --add-port=${port}/udp --permanent
    else
        if ! sudo iptables -C INPUT -i "${PROVISIONING_NETWORK_NAME}" -p udp --dport $port -j ACCEPT 2>/dev/null ; then
            sudo iptables -I INPUT -i "${PROVISIONING_NETWORK_NAME}" -p udp --dport $port -j ACCEPT
        fi
    fi
done

# Remove existing pod
if  sudo podman pod exists ironic-pod ; then
    sudo podman pod rm ironic-pod -f
fi

# Create pod
sudo podman pod create -n ironic-pod

# Download IPA images
sudo podman run -d --net host --privileged --name httpd-${PROVISIONING_NETWORK_NAME} --pod ironic-pod \
     --env PROVISIONING_INTERFACE=${PROVISIONING_NETWORK_NAME} \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/runhttpd ${IRONIC_IMAGE}

sudo podman run -d --net host --privileged --name ipa-downloader --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared ${IRONIC_IPA_DOWNLOADER_IMAGE} /usr/local/bin/get-resource.sh

# Start BMC emulators
if [ "$NODES_PLATFORM" = "libvirt" ]; then
    sudo podman run -d --net host --privileged --name vbmc --pod ironic-pod \
         -v "$WORKING_DIR/virtualbmc/vbmc":/root/.vbmc -v "/root/.ssh":/root/ssh \
         "${VBMC_IMAGE}"

    sudo podman run -d --net host --privileged --name sushy-tools --pod ironic-pod \
         -v "$WORKING_DIR/virtualbmc/sushy-tools":/root/sushy -v "/root/.ssh":/root/ssh \
         "${SUSHY_TOOLS_IMAGE}"
fi

# Wait for the downloader container to finish
sudo podman wait -i 1000 ipa-downloader

# Wait for images to be downloaded/ready
while ! curl --fail --head http://$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/images/ironic-python-agent.initramfs ; do sleep 1; done
while ! curl --fail --head http://$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/images/ironic-python-agent.tar.headers ; do sleep 1; done
while ! curl --fail --head http://$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/images/ironic-python-agent.kernel ; do sleep 1; done

# Start dnsmasq, mariadb, and ironic containers using same image
sudo podman run -d --net host --privileged --name dnsmasq  --pod ironic-pod \
     --env DHCP_RANGE="$DHCP_RANGE" \
     --env PROVISIONING_INTERFACE="${PROVISIONING_NETWORK_NAME}" \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/rundnsmasq ${IRONIC_IMAGE}

mariadb_password=$(echo $(date;hostname)|sha256sum |cut -c-20)
sudo podman run -d --net host --privileged --name mariadb --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/runmariadb \
     --env MARIADB_PASSWORD=$mariadb_password ${IRONIC_IMAGE}

# Start Ironic Inspector
sudo podman run -d --net host --privileged --name ironic-inspector \
     --env PROVISIONING_INTERFACE="${PROVISIONING_NETWORK_NAME}" \
     --pod ironic-pod -v $IRONIC_DATA_DIR:/shared "${IRONIC_INSPECTOR_IMAGE}"

generate_clouds_yaml

[ ${IRONIC_INSPECTOR_ONLY:-0} -eq 0 ] || exit 0

sudo podman run -d --net host --privileged --name ironic-conductor --pod ironic-pod \
     --env MARIADB_PASSWORD=$mariadb_password \
     --env OS_CONDUCTOR__HEARTBEAT_TIMEOUT=120 \
     --env PROVISIONING_INTERFACE="${PROVISIONING_NETWORK_NAME}" \
     --entrypoint /bin/runironic-conductor \
     -v $IRONIC_DATA_DIR:/shared ${IRONIC_IMAGE}

sudo podman run -d --net host --privileged --name ironic-api --pod ironic-pod \
     --env MARIADB_PASSWORD=$mariadb_password \
     --entrypoint /bin/runironic-api \
     --env PROVISIONING_INTERFACE="${PROVISIONING_NETWORK_NAME}" \
     -v $IRONIC_DATA_DIR:/shared ${IRONIC_IMAGE}

# Make sure Ironic is up
export OS_URL=http://localhost:6385

wait_for_json ironic \
    "${OS_URL}/v1/nodes" \
    20 \
    -H "Accept: application/json"

if [ $(sudo podman ps | grep -w -e "ironic-api$" -e "ironic-conductor$" -e "ironic-inspector$" -e "dnsmasq" -e "httpd" | wc -l) != 5 ]; then
    echo "Can't find required containers"
    exit 1
fi

sudo cp -f "$WORKING_DIR/ironic_nodes.json" ~/local_nodes.json
sudo chown $USER ~/local_nodes.json

echo "Ironic installed locally and serving on $OS_URL, export OS_CLOUD=ironic"
echo "Use ~/local_nodes.json as an inventory file for enrolling nodes"
echo "Run ./ironic_cleanup.sh && ./04_setup_ironic.sh before installing cluster"
