#!/bin/bash

NETWORK_NAME=${CLUSTER_NAME}bm
FILENAME=/var/lib/libvirt/dnsmasq/${NETWORK_NAME}.hostsfile

# We need to keep running even after setting the infinite leases because
# they are overwritten multiple times in the deployment process.
while :
do
    if grep -q -v infinite $FILENAME
    then
        sudo perl -pi -e 's/(.*?)(,infinite|)$/\1,infinite/' $FILENAME

        pid=$(ps aux | grep dnsmasq | grep "$NETWORK_NAME" | grep -v root | awk '{print $2}')
        sudo kill -s SIGHUP $pid
        echo "Added infinite leases to $FILENAME"
    fi
    sleep 10
done
