# Get the git commit that the openshift installer was built from
OPENSHIFT_INSTALL_COMMIT=$($OPENSHIFT_INSTALLER version | grep commit | cut -d' ' -f4)

# Get the rhcos.json for that commit
OPENSHIFT_INSTALLER_MACHINE_OS=${OPENSHIFT_INSTALLER_MACHINE_OS:-https://raw.githubusercontent.com/openshift/installer/$OPENSHIFT_INSTALL_COMMIT/data/data/rhcos.json}

# Get the rhcos.json for that commit, and find the baseURI and openstack image path
MACHINE_OS_IMAGE_JSON=$(curl "${OPENSHIFT_INSTALLER_MACHINE_OS}")
export MACHINE_OS_INSTALLER_IMAGE_URL=$(echo "${MACHINE_OS_IMAGE_JSON}" | jq -r '.baseURI + .images.openstack.path')
export MACHINE_OS_IMAGE_URL=${MACHINE_OS_IMAGE_URL:-${MACHINE_OS_INSTALLER_IMAGE_URL}}
export MACHINE_OS_IMAGE_FILENAME_LATEST="rhcos-ootpa-latest.qcow2"
