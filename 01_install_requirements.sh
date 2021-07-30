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
  git reset 8908da5241d52e25a7e1b2e60d6d604cf797f890 --hard
  popd
fi

# Update to latest packages first
sudo dnf -y upgrade

# Install additional repos as needed for each OS version
# shellcheck disable=SC1091
source /etc/os-release
export DISTRO="${ID}${VERSION_ID%.*}"
if [[ $DISTRO == "centos8" ]]; then
    sudo dnf -y install epel-release dnf --enablerepo=extras
    # Advanced virt repo provides newer libvirt with NATv6 support
    sudo dnf -y install centos-release-advanced-virtualization
fi


# Install ansible, other packages are installed via
# vm-setup/install-package-playbook.yml
sudo dnf -y install python3 python3-pip
sudo alternatives --set python /usr/bin/python3
pip3 install --user ansible=="${ANSIBLE_VERSION}"

pushd ${METAL3_DEV_ENV_PATH}
ansible-galaxy install -r vm-setup/requirements.yml
ansible-galaxy collection install ansible.netcommon ansible.posix
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "virthost=$HOSTNAME" \
  -e "go_version=1.14.4" \
  -i vm-setup/inventory.ini \
  -b -vvv vm-setup/install-package-playbook.yml
popd

# We use yq in a few places for processing YAML but it isn't packaged
# for CentOS/RHEL so we have to install from pip.
pip3 install --user 'yq>=2.10.0'

# needed if we are using locally built images
# We stop any systemd service so we can run in a container, since
# there's no RPM/systemd version available for RHEL8
if sudo systemctl is-active docker-distribution.service; then
  sudo systemctl disable --now docker-distribution.service
fi

retry_with_timeout 5 60 "curl $OPENSHIFT_CLIENT_TOOLS_URL | sudo tar -U -C /usr/local/bin -xzf -"
sudo chmod +x /usr/local/bin/oc
oc version --client -o json
