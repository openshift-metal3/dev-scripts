#!/usr/bin/env bash
set -x

source logging.sh
source common.sh

# Kill and remove the running ironic containers
for name in ironic ironic-api ironic-conductor ironic-inspector dnsmasq httpd-${PROVISIONING_NETWORK_NAME} mariadb vbmc sushy-tools; do
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name -f
done

# Remove stale virtualbmc PID
sudo rm -f $WORKING_DIR/virtualbmc/vbmc/master.pid

# Remove existing pod
if  sudo podman pod exists ironic-pod ; then
    sudo podman pod rm ironic-pod -f
fi
