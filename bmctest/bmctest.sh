#!/usr/bin/env bash

set -eu

# bmctest.sh tests the hosts from the supplied yaml config file
# are working with the required ironic opperations (register, power, virtual media)

# FIXME stable URL?
export ISO="fedora-coreos-37.20230205.3.0-live.x86_64.iso"
ISO_URL="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230205.3.0/x86_64/$ISO"
# use the upstream ironic image by default
IRONICIMAGE="quay.io/metal3-io/ironic:latest"

function usage {
    echo "USAGE:"
    echo "./$(basename "$0") [-i ironic_image] -I interface -s pull_secret.json -c config.yaml"
    echo "ironic image defaults to $IRONICIMAGE"
}

while getopts "i:I:s:c:h" opt; do
    case $opt in
        h) usage; exit 0 ;;
        i) IRONICIMAGE=$OPTARG ;;
        I) INTERFACE=$OPTARG ;;
        s) PULL_SECRET=$OPTARG ;;
        c) CONFIGFILE=$OPTARG ;;
        ?) usage; exit 1 ;;
    esac
done

if [[ -z ${INTERFACE:-} ]]; then
    echo "you must provide the network interface"
    usage
    exit 1
fi

# FIXME pull secret not needed when using upstream ironic image
if [[ ! -e ${CONFIGFILE:-} || ! -e ${PULL_SECRET:-} ]]; then
    echo "invalid config file or pull secret file"
    usage
    exit 1
fi

function timestamp {
    echo -n "$(date +%T) "
    echo "$1"
}
export -f timestamp

ERROR_FILE=$(mktemp)
export ERROR_FILE
function cleanup {
    timestamp "cleaning up - removing container"
    sudo podman rm -f -t 0 bmctest
    rm -rf "$ERROR_FILE"
}
trap "cleanup" EXIT

timestamp "checking / installing GNU parallel"
if ! which parallel > /dev/null 2>&1; then
    sudo dnf install -y parallel
    mkdir -p ~/.parallel
    touch ~/.parallel/will-cite
fi

timestamp "checking / getting ISO image"
if sudo [ ! -e /srv/ironic/html/images/${ISO} ]; then
    sudo mkdir -p /srv/ironic/html/images/
    sudo curl -L $ISO_URL -o /srv/ironic/html/images/${ISO}
fi

timestamp "checking / cleaning old container"
sudo podman rm -f -t 0 bmctest

timestamp "checking TCP 80 port is not already in use"
if nc -z localhost 80; then
    echo "ERROR: HTTP port already in use, exiting"
    exit 1
fi

# FIXME run baremetal cli and configure it with clouds.yaml inside the container
timestamp "starting ironic container"
sudo podman run --authfile "$PULL_SECRET" --rm -d --net host --env PROVISIONING_INTERFACE="${INTERFACE}" \
    -v /srv/ironic:/shared --name bmctest --entrypoint sleep "$IRONICIMAGE" infinity

# starting ironic
timestamp "starting ironic process"
sudo podman exec -d bmctest bash -c "runironic > /tmp/ironic.log 2>&1"

# starting httpd
timestamp "starting httpd process"
sudo podman exec -d bmctest bash -c "/bin/runhttpd > /tmp/httpd.log 2>&1"

# FIXME - take --wait as argument to script
# create function for repeated "if EXIT ERRORS return" code
function test_manage {
    local name=$1; local address=$2; local systemid=$3; local user=$4; local pass=$5
    baremetal node create --boot-interface redfish-virtual-media --driver redfish \
        --driver-info redfish_address="${address}" --driver-info redfish_system_id="${systemid}" \
        --driver-info redfish_verify_ca=False --driver-info redfish_username="${user}" \
        --driver-info redfish_password="${pass}" --property capabilities='boot_mode:uefi' \
        --name "${name}" > /dev/null
    echo -n "    " # indent baremetal output
    if ! baremetal node manage "${name}" --wait 60; then
        echo "can not manage node ${name}" >> "$ERROR_FILE"
        return 1
    fi
}
export -f test_manage

function test_power {
    local name=$1
    for power in on off; do
        if ! baremetal node power "$power" "$name" --power-timeout 60; then
            echo "can not power $power ${name}" >> "$ERROR_FILE"
            return 1
        fi
    done
}
export -f test_power

function test_boot_vmedia {
    local name=$1
    # FIXME for Dell we might need idrac-virtualmedia
    baremetal node set "$name" --boot-interface redfish-virtual-media --deploy-interface ramdisk \
    --instance-info boot_iso="http://localhost/images/${ISO}"
    baremetal node set "$name" --no-automated-clean
    echo -n "    " # indent baremetal output
    baremetal node provide --wait 60 "$name"
    echo -n "    " # indent baremetal output
    if ! baremetal node deploy --wait 120 "$name"; then
        echo "failed to boot node $name from ISO" >> "$ERROR_FILE"
        return 1
    fi
}
export -f test_boot_vmedia

function test_boot_device {
    local name=$1
    if ! baremetal node boot device set "$name" pxe; then
        echo "failed to switch boot device to PXE on $name" >> "$ERROR_FILE"
        return 1
    fi
}
export -f test_boot_device

function test_eject_media {
   local name=$1
   if ! baremetal node passthru call "$name" eject_vmedia; then
        echo "failed to eject media on $name" >> "$ERROR_FILE"
        return 1
    fi
}
export -f test_eject_media

function test_node {
    local name=$1; local address=$2; local systemid=$3; local user=$4; local pass=$5
    echo; echo "===== $name ====="

    timestamp "attempting to manage $name (check address & credentials)"
    if test_manage "$name" "$address" "$systemid" "$user" "$pass"; then
       echo "    success"
    else
       echo "    failed to manage $name - can not run further tests on node"
       return 0
    fi

    timestamp "testing ability to power on/off $name"
    if test_power "$name"; then
        echo "    success"
    fi

    timestamp "verifying node boot device can be set on $name"
    if test_boot_device "$name"; then
        echo "    success"
    fi

    timestamp "testing booting from redfish-virtual-media on $name"
    if test_boot_vmedia "$name"; then
        echo "    success"
    fi

    timestamp "testing vmedia detach on $name"
    if test_eject_media "$name"; then
        echo "    success"
    fi
}
export -f test_node

timestamp "testing, can take several minutes, please wait for results ..."
yq -r '.hosts[] | "\(.name) \(.bmc.address) \(.bmc.systemid) \(.bmc.username) \(.bmc.password)"' "$CONFIGFILE" | \
    parallel --colsep ' ' -a - test_node

EXIT=$(wc -l "$ERROR_FILE" | cut -d ' '  -f 1)
echo; echo "========== Found $EXIT errors =========="
cat "$ERROR_FILE"
echo
exit "$EXIT"
