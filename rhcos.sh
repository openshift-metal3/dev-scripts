# Get the git commit that the openshift installer was built from
OPENSHIFT_INSTALL_COMMIT=$($OPENSHIFT_INSTALLER version | grep commit | cut -d' ' -f4)

# Get the rhcos.json for that commit
OPENSHIFT_INSTALLER_MACHINE_OS=${OPENSHIFT_INSTALLER_MACHINE_OS:-https://raw.githubusercontent.com/openshift/installer/$OPENSHIFT_INSTALL_COMMIT/data/data/rhcos.json}

# Get the rhcos.json for that commit, and find the baseURI and openstack image path
MACHINE_OS_IMAGE_JSON=$(curl "${OPENSHIFT_INSTALLER_MACHINE_OS}")

export MACHINE_OS_INSTALLER_IMAGE_URL=$(echo "${MACHINE_OS_IMAGE_JSON}" | jq -r '.baseURI + .images.openstack.path')
export MACHINE_OS_INSTALLER_IMAGE_SHA256=$(echo "${MACHINE_OS_IMAGE_JSON}" | jq -r '.images.openstack.sha256')
export MACHINE_OS_IMAGE_URL=${MACHINE_OS_IMAGE_URL:-${MACHINE_OS_INSTALLER_IMAGE_URL}}
export MACHINE_OS_IMAGE_NAME=$(basename ${MACHINE_OS_IMAGE_URL})
export MACHINE_OS_IMAGE_SHA256=${MACHINE_OS_IMAGE_SHA256:-${MACHINE_OS_INSTALLER_IMAGE_SHA256}}

export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_URL=$(echo "${MACHINE_OS_IMAGE_JSON}" | jq -r '.baseURI + .images.qemu.path')
export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_SHA256=$(echo "${MACHINE_OS_IMAGE_JSON}" | jq -r '.images.qemu.sha256')
export MACHINE_OS_BOOTSTRAP_IMAGE_URL=${MACHINE_OS_BOOTSTRAP_IMAGE_URL:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_URL}}
export MACHINE_OS_BOOTSTRAP_IMAGE_NAME=$(basename ${MACHINE_OS_BOOTSTRAP_IMAGE_URL})
export MACHINE_OS_BOOTSTRAP_IMAGE_SHA256=${MACHINE_OS_BOOTSTRAP_IMAGE_SHA256:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_SHA256}}

# FIXME the installer cache expects an uncompressed sha256
# https://github.com/openshift/installer/issues/2845
export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256=$(echo "${MACHINE_OS_IMAGE_JSON}" | jq -r '.images.qemu["uncompressed-sha256"]')
export MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}}

# Temporary: Use sha256 sums from local storage if present, to make sure
# we use what was calculated after editing the bootstrap image.
temporary_sha256_hack() {
    BOOTSTRAP_IMAGE_FILE="${IRONIC_DATA_DIR}/html/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}"
    BOOTSTRAP_IMAGE_SHA256_FILE="${BOOTSTRAP_IMAGE_FILE}.sha256sum"
    UNCOMPRESSED_BOOTSTRAP_IMAGE_FILE="$(echo "${BOOTSTRAP_IMAGE_FILE}" | sed -e 's/\.gz//')"
    UNCOMPRESSED_BOOTSTRAP_IMAGE_SHA256_FILE="${UNCOMPRESSED_BOOTSTRAP_IMAGE_FILE}.sha256sum"

    if [ ! -f "${UNCOMPRESSED_BOOTSTRAP_IMAGE_SHA256_FILE}" ]; then
        return
    fi

    export MACHINE_OS_BOOTSTRAP_IMAGE_SHA256=$(cat "${BOOTSTRAP_IMAGE_SHA256_FILE}" | awk '{print $1}')
    export MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256=$(cat "${UNCOMPRESSED_BOOTSTRAP_IMAGE_SHA256_FILE}" | awk '{print $1}')
}
temporary_sha256_hack

hack_rhcos_bootstrap_image() {
    if [[ "${USE_IPV4}" = "true" ]]; then
        # Don't hack the image if using IPv4
        return
    fi
    if [[ "${OPENSHIFT_RELEASE_IMAGE}" == *"4.5"* ]]; then
        # Not needed in 4.5 as of https://github.com/openshift/installer/pull/3257
        return
    fi

    IMAGE_FILE="$1"
    IMAGE_SHA256_FILE="${IMAGE_FILE}.sha256sum"
    UNCOMPRESSED_IMAGE_FILE="$(echo "${IMAGE_FILE}" | sed -e 's/\.gz//')"
    UNCOMPRESSED_IMAGE_SHA256_FILE="${UNCOMPRESSED_IMAGE_FILE}.sha256sum"

    pushd $(dirname "${IMAGE_FILE}")

    gunzip "${IMAGE_FILE}"
    set +e
    IP_PARAM=$(virt-cat -a "${UNCOMPRESSED_IMAGE_FILE}" -m /dev/sda1 /grub2/grub.cfg | grep "ip=ens3:dhcp6")
    set -e
    if [[ -n "${IP_PARAM}" ]] ; then
        # Image already successfully hacked
        gzip "${UNCOMPRESSED_IMAGE_FILE}"
        popd
        return
    fi

    # Fix the ip= kernel command line to work for IPv6.  This is temporary.
    virt-edit -a "${UNCOMPRESSED_IMAGE_FILE}" -m /dev/sda1 -e "s/ip=dhcp/ip=ens3:dhcp6/g" /grub2/grub.cfg

    echo "$(sha256sum "${UNCOMPRESSED_IMAGE_FILE}" | awk '{print $1}') ${UNCOMPRESSED_IMAGE_FILE}" > "${UNCOMPRESSED_IMAGE_SHA256_FILE}"
    gzip "${UNCOMPRESSED_IMAGE_FILE}"
    echo "$(sha256sum "${IMAGE_FILE}" | awk '{print $1}') ${IMAGE_FILE}" > "${IMAGE_SHA256_FILE}"

    popd
}
