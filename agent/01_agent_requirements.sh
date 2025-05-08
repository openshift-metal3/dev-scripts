#!/bin/bash

set -o pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/agent/common.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/ocp_install_env.sh
source $SCRIPTDIR/validation.sh

early_deploy_validation

if [[ -z ${AGENT_E2E_TEST_SCENARIO} ]]; then
    printf "\nAGENT_E2E_TEST_SCENARIO is missing or empty. Did you forget to set the AGENT_E2E_TEST_SCENARIO env var in the config_<USER>.sh file?"
    invalidAgentValue
fi

if [[ ${REGISTRY_BACKEND} = "quay" ]]; then

   mkdir -p ${WORKING_DIR}/mirror-registry
   pushd ${WORKING_DIR}/mirror-registry
   # run the exec in this dir as execution-environment.tar is also needed
   mirror_registry_file=mirror-registry.tar.gz
   mirror_registry_exec=${mirror_registry_file%%.*}
   if [[ ! -f "./${mirror_registry_exec}" ]]; then
      curl -O -L https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/${mirror_registry_file}
      tar xzf ${mirror_registry_file}
      chmod +x ${mirror_registry_exec}
      rm -f ${mirror_registry_file}
   fi
   popd

fi

if [[ "${MIRROR_COMMAND}" == oc-mirror ]]; then

   oc_mirror_file=oc-mirror.tar.gz
   oc_mirror_exec=${oc_mirror_file%%.*}
   if [[ ! -f "/usr/local/bin/${oc_mirror_exec}" ]]; then
      curl -O -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/${oc_mirror_file}
      tar xzf ${oc_mirror_file}
      chmod +x ${oc_mirror_exec}
      sudo mv -f ${oc_mirror_exec} /usr/local/bin
      rm -f ${oc_mirror_file}
   fi
fi

if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISCSI" ]]; then
    # Install shell to administer local storage
    sudo dnf -y install targetcli
fi

if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISO_NO_REGISTRY" ]]; then
   sudo dnf -y install xorriso coreos-installer syslinux skopeo
fi

if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "DISKIMAGE" ]]; then
   MIN_SPACE_REQUIRED=300
   source $SCRIPTDIR/sanitychecks.sh
fi
