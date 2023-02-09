#!/usr/bin/env bash

set -eu

# bmctest.sh tests the hosts from the supplied yaml config file
# are working with the required ironic opperations (register, power, virtual media)

# FIXME use fedora or other Red Hat image
ISO="archlinux-2023.02.01-x86_64.iso"
ISO_URL="https://geo.mirror.pkgbuild.com/iso/2023.02.01/$ISO"
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

function cleanup {
    timestamp "cleaning up - removing container"
    sudo podman rm -f -t 0 bmctest
}
trap "cleanup" EXIT

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

EXIT=0
ERRORS=""

# FIXME - take --wait as argument to script
# create function for repeated "if EXIT ERRORS return" code
function manage {
    local name=$1; local address=$2; local systemid=$3; local user=$4; local pass=$5
    baremetal node create --boot-interface redfish-virtual-media --driver redfish \
        --driver-info redfish_address="${address}" --driver-info redfish_system_id="${systemid}" \
        --driver-info redfish_verify_ca=False --driver-info redfish_username="${user}" \
        --driver-info redfish_password="${pass}" --property capabilities='boot_mode:uefi' \
        --name "${name}" > /dev/null
    echo -n "    " # indent baremetal output
    if ! baremetal node manage "${name}" --wait 60; then
        EXIT=$((EXIT + 1))
        ERRORS+="can not manage node ${name}\n"
        return 1
    fi
}

function power {
    local name=$1
    for power in on off; do
        if ! baremetal node power "$power" "$name" --power-timeout 60; then
            EXIT=$((EXIT + 1))
            ERRORS+="can not power $power ${name}\n"
            return 1
        fi
    done
}

function boot_vmedia {
    local name=$1
    # FIXME for Dell we might need idrac-virtualmedia
    baremetal node set "$name" --boot-interface redfish-virtual-media --deploy-interface ramdisk \
    --instance-info boot_iso="http://localhost/images/${ISO}"
    baremetal node set "$name" --no-automated-clean
    echo -n "    " # indent baremetal output
    baremetal node provide --wait 60 "$name"
    echo -n "    " # indent baremetal output
    if ! baremetal node deploy --wait 120 "$name"; then
        EXIT=$((EXIT + 1))
        ERROS+="failed to boot node $name from ISO"
        return 1
    fi
}

function boot_device {
    local name=$1
    # this is called after boot_vmedia which sets the boot device as cdrom
    # so we test with setting it to pxe
    if ! baremetal node boot device set "$name" pxe; then
        EXIT=$((EXIT + 1))
        ERROS+="failed to switch boot device to PXE on $name"
        return 1
    fi
}

function eject_media {
   local name=$1
   if ! baremetal node passthru call "$name" eject_vmedia; then
        EXIT=$((EXIT + 1))
        ERROS+="failed to eject media on $name"
        return 1
    fi
}

# FIXME - use gnu parallel or something of the sort
while read -r NAME ADDRESS SYSTEMID USERNAME PASSWORD; do
    echo; timestamp "===== $NAME ====="

    timestamp "attempting to manage $NAME (check address & credentials)"
    if manage "$NAME" "$ADDRESS" "$SYSTEMID" "$USERNAME" "$PASSWORD"; then
       echo "    success"
    else
       continue
    fi

    timestamp "testing ability to power on/off $NAME"
    power "$NAME" && echo "    success"

    timestamp "testing booting from redfish-virtual-media on $NAME"
    if boot_vmedia "$NAME"; then
        echo "    success"
    else
       continue
    fi

    timestamp "verifying node boot device can be set"
    boot_device "$NAME" && echo "    success"

    timestamp "testing vmedia detach" # may need to actually provision a live-iso image
    eject_media "$NAME" && echo "    success"
done < <(yq -r '.hosts[] | "\(.name) \(.bmc.address) \(.bmc.systemid) \(.bmc.username) \(.bmc.password)"' "$CONFIGFILE")

echo; timestamp "========== Found $EXIT errors =========="
echo -e "$ERRORS"
exit $EXIT
