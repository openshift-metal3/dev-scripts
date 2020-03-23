if [[ -f "$OCP_DIR/rhcos.json" ]]; then
  MACHINE_OS_IMAGE_JSON=$(cat "$OCP_DIR/rhcos.json")
else

	if [[ -v JOB_NAME ]] && [[ "$JOB_NAME" =~ "openshift-installer" ]]; then
		# Get the SHA from the PR if we're in CI
  	OPENSHIFT_INSTALL_COMMIT=${PULL_PULL_SHA:-$(echo "$JOB_SPEC" | jq -r '.refs.pulls[0].sha')}
	else
  	# Get the git commit that the openshift installer was built from
	  OPENSHIFT_INSTALL_COMMIT=$($OPENSHIFT_INSTALLER version | grep commit | cut -d' ' -f4)
	fi

  # Get the git commit that the openshift installer was built from
  OPENSHIFT_INSTALL_COMMIT=$($OPENSHIFT_INSTALLER version | grep commit | cut -d' ' -f4)

  # Get the rhcos.json for that commit
  OPENSHIFT_INSTALLER_MACHINE_OS=${OPENSHIFT_INSTALLER_MACHINE_OS:-https://raw.githubusercontent.com/openshift/installer/$OPENSHIFT_INSTALL_COMMIT/data/data/rhcos.json}

  # Get the rhcos.json for that commit, and find the baseURI and openstack image path
  MACHINE_OS_IMAGE_JSON=$(curl "${OPENSHIFT_INSTALLER_MACHINE_OS}")
fi

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
