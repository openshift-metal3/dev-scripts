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
  git reset ee1b2fec44e22700c8d250d5e0e371e3fd0aba17 --hard
  popd
fi

# This must be aligned with the metal3-dev-env pinned version above, see
# https://github.com/metal3-io/metal3-dev-env/blob/master/lib/common.sh
export ANSIBLE_VERSION=${ANSIBLE_VERSION:-"4.8.0"}

# Update to latest packages first
sudo dnf -y upgrade

# Install additional repos as needed for each OS version
# shellcheck disable=SC1091
source /etc/os-release
export DISTRO="${ID}${VERSION_ID%.*}"
if [[ $DISTRO == "centos8" ]]; then
    if [ "$NAME" != "CentOS Stream" -a ! -e /etc/yum.repos.d/centos-vault.repo ] ; then
        # Centos8 is EOL
        mv /etc/yum.repos.d /etc/yum.repos.d_$(date +%s)
        mkdir /etc/yum.repos.d
        echo -e '[base]\nname=base\nbaseurl=https://vault.centos.org/8.4.2105/BaseOS/x86_64/os/\ngpgcheck=0\nenabled=1\n[apps]\nname=apps\nbaseurl=https://vault.centos.org/8.4.2105/AppStream/x86_64/os/\ngpgcheck=0\nenabled=1\n[extras]\nname=extras\nbaseurl=https://vault.centos.org/8.4.2105/extras/x86_64/os/\ngpgcheck=0\nenabled=1' > /etc/yum.repos.d/centos-vault.repo
    fi

    sudo dnf install -y dnf-plugins-core
    sudo dnf config-manager --set-enabled powertools
    sudo dnf install -y epel-release epel-next-release
elif [[ $DISTRO == "rhel8" ]]; then
    # Enable EPEL for python3-passlib and python3-bcrypt required by metal3-dev-env
    sudo subscription-manager repos --enable codeready-builder-for-rhel-8-$(arch)-rpms
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm

    # The packaged 2.x ansible is too old for compatibility with metal3-dev-env
    sudo dnf erase -y ansible
    sudo subscription-manager repos --disable=ansible-2-for-rhel-8-x86_64-rpms
fi

# Install ansible, other packages are installed via
# vm-setup/install-package-playbook.yml
# Note recent ansible needs python >= 3.8 so we install 3.9 here
sudo dnf -y install python39
sudo alternatives --set python /usr/bin/python3.9
sudo alternatives --set python3 /usr/bin/python3.9
sudo update-alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.9 1
sudo pip3 install ansible=="${ANSIBLE_VERSION}"
# Also need the 3.9 version of netaddr for ansible.netcommon
# and lxml for the pyxpath script
sudo pip3 install netaddr lxml

pushd ${METAL3_DEV_ENV_PATH}
ansible-galaxy install -r vm-setup/requirements.yml
ansible-galaxy collection install --upgrade ansible.netcommon ansible.posix community.general
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "virthost=$HOSTNAME" \
  -e "go_version=1.17.1" \
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
