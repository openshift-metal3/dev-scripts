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
  git reset a994b1447f89e20ec9cc161700a9e829fd5d4b89 --hard
  popd
fi

# This must be aligned with the metal3-dev-env pinned version above, see
# https://github.com/metal3-io/metal3-dev-env/blob/master/lib/common.sh
export ANSIBLE_VERSION=${ANSIBLE_VERSION:-"7.1.0"}

# Speed up dnf downloads
sudo sh -c "echo 'fastestmirror=1' >> /etc/dnf/dnf.conf"
sudo sh -c "echo 'max_parallel_downloads=8' >> /etc/dnf/dnf.conf"

# Refresh dnf data
# We could also use --refresh to just force metadata update
# in the upgrade command,but this is more explicit and complete
sudo dnf -y clean all

# Update to latest packages first
sudo dnf -y upgrade --nobest

# If NetworkManager was upgraded it needs to be restarted
sudo systemctl restart NetworkManager

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
  "centos8"|"rhel8"|"almalinux8"|"rocky8")
    # install network-scripts package to be able to use legacy network commands
    sudo dnf install -y network-scripts
    if [[ $DISTRO == "centos8" ]] && [[ "$NAME" != *"Stream"* ]]; then
        echo "CentOS is not supported, please switch to CentOS Stream / RHEL / Rocky / Alma"
        exit 1
    fi
    if [[ $DISTRO == "centos8" || $DISTRO == "almalinux8" || $DISTRO == "rocky8" ]]; then
      sudo dnf -y install epel-release dnf --enablerepo=extras
    elif [[ $DISTRO == "rhel8" ]]; then
      # Enable EPEL for python3-passlib and python3-bcrypt required by metal3-dev-env
      sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
      if sudo subscription-manager repos --list-enabled 2>&1 | grep "ansible-2-for-rhel-8-$(uname -m)-rpms"; then
        # The packaged 2.x ansible is too old for compatibility with metal3-dev-env
        sudo dnf erase -y ansible
        sudo subscription-manager repos --disable=ansible-2-for-rhel-8-$(uname -m)-rpms
      fi
    fi
    # Note recent ansible needs python >= 3.8 so we install 3.9 here
    sudo dnf -y install python39
    sudo alternatives --set python /usr/bin/python3.9
    sudo alternatives --set python3 /usr/bin/python3.9
    sudo update-alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.9 1
    ;;
  "centos9"|"rhel9"|"rocky9")
    sudo dnf -y install python3-pip
    if [[ $DISTRO == "centos9" ]] ||[[ $DISTRO == "rocky9" ]] ; then
      sudo dnf config-manager --set-enabled crb
      sudo dnf -y install epel-release
    elif [[ $DISTRO == "rhel9" ]]; then
      sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    fi
    sudo ln -s /usr/bin/python3 /usr/bin/python || true
    ;;
  *)
    echo -n "CentOS or RHEL version not supported"
    exit 1
    ;;
esac

# Hijack metal3-dev-env update module to use nobest
# during dnf upgrade
sudo dnf -y install jq
sudo python -m pip install yq
yq -iy '.[3].dnf.nobest = "true"' ${METAL3_DEV_ENV_PATH}/vm-setup/roles/packages_installation/tasks/centos_required_packages.yml

GO_VERSION=${GO_VERSION:-1.22.3}

GOARCH=$(uname -m)
if [[ $GOARCH == "aarch64" ]]; then
    GOARCH="arm64"
    sudo dnf -y install python39-devel libxml2-devel libxslt-devel
elif [[ $GOARCH == "x86_64" ]]; then
    GOARCH="amd64"
fi

# Also need the 3.9 version of netaddr for ansible.netcommon
# and lxml for the pyxpath script
sudo python -m pip install netaddr lxml

sudo python -m pip install ansible=="${ANSIBLE_VERSION}"

pushd ${METAL3_DEV_ENV_PATH}
ansible-galaxy install -r vm-setup/requirements.yml
ansible-galaxy collection install --upgrade ansible.netcommon ansible.posix ansible.utils community.general
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "virthost=$HOSTNAME" \
  -e "go_version=$GO_VERSION" \
  -e "GOARCH=$GOARCH" \
  $ALMA_PYTHON_OVERRIDE \
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

# We use yq in a few places for processing YAML but it isn't packaged
# for CentOS/RHEL so we have to install from pip. We do not want to
# overwrite an existing installation of the golang version, though,
# so check if we have a yq before installing.
if ! which yq 2>&1 >/dev/null; then
    sudo python -m pip install 'yq>=2.10.0'
else
    echo "Using yq from $(which yq)"
fi

# needed if we are using locally built images
# We stop any systemd service so we can run in a container, since
# there's no RPM/systemd version available for RHEL8
if sudo systemctl is-active docker-distribution.service; then
  sudo systemctl disable --now docker-distribution.service
fi

retry_with_timeout 5 60 "curl $OPENSHIFT_CLIENT_TOOLS_URL | sudo tar -U -C /usr/local/bin -xzf -"
sudo chmod +x /usr/local/bin/oc
oc version --client -o json
