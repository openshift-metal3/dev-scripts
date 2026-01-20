#!/usr/bin/env bash
set -ex


source logging.sh
source common.sh
source sanitychecks.sh
source utils.sh
source validation.sh

early_deploy_validation true

if [ -z "${METAL3_DEV_ENV}" ]; then
  export REPO_PATH=${WORKING_DIR}
  sync_repo_and_patch metal3-dev-env https://github.com/metal3-io/metal3-dev-env.git
  pushd ${METAL3_DEV_ENV_PATH}
  # Pin to a specific metal3-dev-env commit to ensure we catch breaking
  # changes before they're used by everyone and CI.
  # TODO -- come up with a plan for continuously updating this
  # Note we only do this in the case where METAL3_DEV_ENV is
  # unset, to enable developer testing of local checkouts
  git reset 61f66daf873de7fc1eb296ea015ee3f7ff289f75 --hard

  popd
fi

# This must be aligned with the metal3-dev-env pinned version above, see
# https://github.com/metal3-io/metal3-dev-env/blob/master/lib/common.sh
export ANSIBLE_VERSION=${ANSIBLE_VERSION:-"8.7.0"}

# Speed up dnf downloads
sudo sh -c "echo 'fastestmirror=1' >> /etc/dnf/dnf.conf"
sudo sh -c "echo 'max_parallel_downloads=8' >> /etc/dnf/dnf.conf"

# Refresh dnf data
# We could also use --refresh to just force metadata update
# in the upgrade command,but this is more explicit and complete
sudo dnf -y clean all

old_version=$(sudo dnf info NetworkManager | grep Version | cut -d ':' -f 2)

# Update to latest packages first
# Number of attempts
MAX_RETRIES=5
# Delay between attempts (in seconds)
_YUM_RETRY_BACKOFF=15

attempt=1
while (( attempt <= MAX_RETRIES )); do
    if sudo dnf -y upgrade --nobest; then
        echo "System upgraded successfully."
        break
    else
        echo "Upgrade failed (attempt $attempt). Cleaning cache and retrying..."
        sudo dnf clean all
        sudo rm -rf /var/cache/dnf/*
        sleep $(( _YUM_RETRY_BACKOFF * attempt ))
    fi

    (( attempt++ ))
done

if (( attempt > MAX_RETRIES )); then
    echo "ERROR: Failed to upgrade system after $MAX_RETRIES attempts."
    exit 1
fi

new_version=$(sudo dnf info NetworkManager | grep Version | cut -d ':' -f 2)
# If NetworkManager was upgraded it needs to be restarted
if [ "$old_version" != "$new_version" ]; then
  sudo systemctl restart NetworkManager
fi

# Install additional repos as needed for each OS version
# shellcheck disable=SC1091
source /etc/os-release

# NOTE(elfosardo): Hacks required for legacy and missing things due to bump in
#metal3-dev-env commit hash.
# All of those are needed because we're still behind for OS support.
# passlib needs to be installed as system dependency
if [[ -x "/usr/libexec/platform-python" ]]; then
  sudo /usr/libexec/platform-python -m pip install passlib || sudo dnf -y install python3-pip && sudo /usr/libexec/platform-python -m pip install passlib
fi

# Install ansible, other packages are installed via
# vm-setup/install-package-playbook.yml
case $DISTRO in
  "centos9"|"rhel9"|"almalinux9"|"rocky9")
    sudo dnf -y install python3-pip
    if [[ $DISTRO == "centos9" || $DISTRO == "almalinux9" || $DISTRO == "rocky9" ]] ; then
      sudo dnf config-manager --set-enabled crb
      sudo dnf -y install epel-release
    elif [[ $DISTRO == "rhel9" ]]; then
      # NOTE(raukadah): If a system is subscribed to RHEL subscription then
      # sudo subscription-manager identity will return exit 0 else 1.
      if sudo subscription-manager identity > /dev/null 2>&1; then
	# NOTE(elfosardo): a valid RHEL subscription is needed to be able to
	# enable the CRB repository
	sudo subscription-manager repos --enable codeready-builder-for-rhel-9-$(arch)-rpms
      fi
      sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    fi
    sudo ln -s /usr/bin/python3 /usr/bin/python || true
    PYTHON_DEVEL="python3-devel"
    ;;
  *)
    echo -n "CentOS 9 or RHEL 9 required (el8 is no longer supported due to glibc requirements)"
    exit 1
    ;;
esac

# We use yq in a few places for processing YAML but it isn't packaged
# for CentOS/RHEL so we have to install from pip. We do not want to
# overwrite an existing installation of the golang version, though,
# so check if we have a yq before installing.
if ! which yq 2>&1 >/dev/null; then
    sudo python -m pip install 'yq>=3,<4'
else
    echo "Using yq from $(which yq)"
fi

GO_VERSION=${GO_VERSION:-1.24.10}
GO_CUSTOM_MIRROR=${GO_CUSTOM_MIRROR:-"https://go.dev/dl"}

GOARCH=$(uname -m)
if [[ $GOARCH == "aarch64" ]]; then
    GOARCH="arm64"
    sudo dnf -y install $PYTHON_DEVEL libxml2-devel libxslt-devel
elif [[ $GOARCH == "x86_64" ]]; then
    GOARCH="amd64"
fi

# Also need the 3.9 version of netaddr for ansible.netcommon
# and lxml for the pyxpath script
sudo python -m pip install netaddr lxml

sudo python -m pip install ansible=="${ANSIBLE_VERSION}"

pushd ${METAL3_DEV_ENV_PATH}
ansible-galaxy install -r vm-setup/requirements.yml
# Let's temporarily pin these collections to the latest compatible with ansible-2.15
#ansible-galaxy collection install --upgrade ansible.netcommon ansible.posix ansible.utils community.general
ansible-galaxy collection install 'ansible.netcommon<8.0.0' ansible.posix 'ansible.utils<6.0.0' community.general
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "virthost=$HOSTNAME" \
  -e "go_version=$GO_VERSION" \
  -e "go_custom_mirror=$GO_CUSTOM_MIRROR" \
  -e "GOARCH=$GOARCH" \
  -i vm-setup/inventory.ini \
  -b -vvv vm-setup/install-package-playbook.yml
popd

if [ -n "${KNI_INSTALL_FROM_GIT}" ]; then
    # zip is required for building the installer from source
    sudo dnf -y install zip
fi

# Install nfs for persistent volumes
if [ "${PERSISTENT_IMAGEREG}" == true ] ; then
    sudo dnf -y install nfs-utils
fi

if [[ "${NODES_PLATFORM}" == "baremetal" ]] ; then
    sudo dnf -y install ipmitool
fi

retry_with_timeout 5 60 "curl -L $OPENSHIFT_CLIENT_TOOLS_URL | sudo tar -U -C /usr/local/bin -xzf -"
sudo chmod +x /usr/local/bin/oc
oc version --client -o json
