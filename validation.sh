#!/bin/bash

set -o pipefail

# Perform some validation steps that we always want done.
function early_either_validation() {
    if [ "$USER" != "root" -a "${XDG_RUNTIME_DIR:-}" == "/run/user/0" ] ; then
        error "Please use a non-root user, WITH a login shell (e.g. su - USER)"
        exit 1
    fi

    # Check if sudo privileges without password
    if ! sudo -n uptime &> /dev/null ; then
        error "sudo without password is required"
        exit 1
    fi

    # Check OS
    if [[ ! $(awk -F= '/^ID=/ { print $2 }' /etc/os-release | tr -d '"') =~ ^(centos|rhel|almalinux|rocky)$ ]]; then
        error "Unsupported OS"
        exit 1
    fi

    # Check CentOS/RHEL version (el8 is no longer supported due to glibc requirements for oc CLI)
    VER=$(awk -F= '/^VERSION_ID=/ { print $2 }' /etc/os-release | tr -d '"' | cut -f1 -d'.')
    if [[ ${VER} -lt 9 ]]; then
        error "CentOS 9 or RHEL 9 are required."
        exit 1
    fi

    # Check d_type support
    FSTYPE=$(df "${FILESYSTEM}" --output=fstype | tail -n 1)

    case ${FSTYPE} in
        'ext4'|'btrfs')
        ;;
        'xfs')
            if [[ $(xfs_info ${FILESYSTEM} | grep -q "ftype=1") ]]; then
                error "XFS filesystem must have ftype set to 1"
                exit 1
            fi
            ;;
        *)
            error "Filesystem not supported"
            exit 1
            ;;
    esac
}

# Perform some validation steps that we only want done when trying to
# build a cluster.
function early_deploy_validation() {

    CHECK_OC_TOOL_PRESENCE=${1:-"false"}

    early_either_validation

    if [ ! -s ${PERSONAL_PULL_SECRET} -a ${OPENSHIFT_RELEASE_TYPE} != "okd" ]; then
        error "${PERSONAL_PULL_SECRET} is missing or empty"
        if [ -n "${PULL_SECRET:-}" ]; then
            error "It looks like you are using the old PULL_SECRET variable."
            error "Please write the contents of that variable to ${PERSONAL_PULL_SECRET} and try again."
            error "Refer to https://github.com/openshift-metal3/dev-scripts#configuration for details."
        else
            error "Get a valid pull secret (json string) from https://cloud.redhat.com/openshift/install/pull-secret"
        fi
        exit 1
    fi

    if [ "${OPENSHIFT_CI}" != "true" -a ${#CI_TOKEN} = 0 -a "${OPENSHIFT_RELEASE_TYPE}" != "okd" ]; then
        error "No valid CI_TOKEN set in ${CONFIG}"
        if [ -n "${PULL_SECRET:-}" ]; then
            error "It looks like you are using the old PULL_SECRET variable."
        fi
        error "Please login to https://console-openshift-console.apps.ci.l2s4.p1.openshiftapps.com/ and copy the token from the login command from the menu in the top right corner to set CI_TOKEN."
        error "Refer to https://github.com/openshift-metal3/dev-scripts#configuration for details."
        exit 1
    fi

    LOGIN_CHECK="true"
    if [ "${CHECK_OC_TOOL_PRESENCE}" == "true" -a ! -x "$(command -v oc)" ]; then
        LOGIN_CHECK="false"
    fi
    # Verify that the token we have is valid
    if [ ${#CI_TOKEN} != 0 -a ${LOGIN_CHECK} == "true" ]; then
        _test_token=$(mktemp --tmpdir "test-token--XXXXXXXXXX")
        _tmpfiles="$_tmpfiles $_test_token"
        if ! oc login https://${CI_SERVER}:6443 --kubeconfig=$_test_token --token=${CI_TOKEN}; then
            error "Please login to https://console-openshift-console.apps.ci.l2s4.p1.openshiftapps.com/ and copy the token from the login command from the menu in the top right corner to set CI_TOKEN."
            error "Refer to https://github.com/openshift-metal3/dev-scripts#configuration for details."
            exit 1
        fi
    fi
}

# Perform validation steps that we only want done when trying to clean
# up.
function early_cleanup_validation() {
    early_either_validation
}
