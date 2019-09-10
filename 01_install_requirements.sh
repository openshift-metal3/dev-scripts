#!/usr/bin/env bash
set -ex

source logging.sh
source common.sh
source utils.sh

if grep -q "Red Hat Enterprise Linux release 8" /etc/redhat-release 2>/dev/null ; then
    RHEL8="True"
fi

sudo yum install -y libselinux-utils
if selinuxenabled ; then
    # FIXME ocp-doit required this so leave permissive for now
    sudo setenforce permissive
    sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config
fi

# Update to latest packages first
if [ "${RHEL8}" = "True" ] ; then
    # workaround https://bugzilla.redhat.com/show_bug.cgi?id=1750866
    sudo yum -y update --nobest
else
    sudo yum -y update
fi

# Install EPEL required by some packages
if [ ! -f /etc/yum.repos.d/epel.repo ] ; then
    if [ "${RHEL8}" = "True" ] ; then
        # TODO(russellb) Fix this when EPEL 8 is available
        # sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        #
        # It's also possible we never need EPEL and everything we would have pulled from there is
        # available through OSP, instead.  There's no OSP release for RHEL 8 yet either, though.
        :
    elif grep -q "Red Hat Enterprise Linux" /etc/redhat-release ; then
        sudo yum -y install http://mirror.centos.org/centos/7/extras/x86_64/Packages/epel-release-7-11.noarch.rpm
    else
        sudo yum -y install epel-release --enablerepo=extras
    fi
fi

# Install required packages
# python-{requests,setuptools} required for tripleo-repos install
if [ "${RHEL8}" = "True" ] ; then
    sudo dnf install -y \
        python36 \
        python3-requests \
        python3-setuptools
    sudo alternatives --set python /usr/bin/python3

    # TODO(russellb) - Install an rpm for this once OSP for RHEL8 is out
    pushd ~
    if [ ! -d crudini ] ; then
        git clone https://github.com/pixelb/crudini
    fi
    pushd crudini
    git pull -r
    sudo pip3 install -U .
    popd ; popd
fi

if [ "${RHEL8}" = "True" ] ; then
    sudo subscription-manager repos --enable=ansible-2-for-rhel-8-x86_64-rpms

    # make sure additional requirments are installed
    sudo yum -y install \
      ansible \
      podman \
      network-scripts \
      ipmitool \
      redhat-lsb-core

    # TODO(russellb) - Install an rpm for this once OSP for RHEL8 is out
    #sudo dnf groupinstall -y "Development Tools"
    # workaround https://bugzilla.redhat.com/show_bug.cgi?id=1750866
    sudo dnf groupinstall -y "Development Tools" --nobest
    sudo dnf install -y python36-devel

    # TODO(russellb) - Install an rpm for this once OSP for RHEL8 is out
    pushd ~
    if [ ! -d virtualbmc ] ; then
        git clone https://git.openstack.org/openstack/virtualbmc
    fi
    pushd virtualbmc
    git pull -r
    sudo pip3 install -U .
    curl 'https://review.rdoproject.org/r/gitweb?p=openstack/virtualbmc-distgit.git;a=blob_plain;f=virtualbmc.service;hb=HEAD' > virtualbmc.service
    sed -i 's|/usr/bin/vbmcd|/usr/local/bin/vbmcd|' virtualbmc.service
    sudo mv virtualbmc.service /etc/systemd/system/.
    sudo systemctl daemon-reload
    popd ; popd

    pushd ~
    if [ ! -d openstackclient ] ; then
        git clone https://git.openstack.org/openstack/openstackclient
    fi
    pushd openstackclient
    git pull -r
    sudo pip3 install -U .
    popd ; popd
else
    # We're reusing some tripleo pieces for this setup so clone them here
    cd
    if [ ! -d tripleo-repos ]; then
      git clone https://git.openstack.org/openstack/tripleo-repos
    fi
    pushd tripleo-repos
    sudo python setup.py install
    popd

    # Needed to get a recent python-virtualbmc package
    sudo tripleo-repos current-tripleo

    # There are some packages which are newer in the tripleo repos
    sudo yum -y update

    # make sure additional requirments are installed
    sudo yum -y install \
      ansible \
      podman \
      redhat-lsb-core
fi

export REPO_PATH=${WORKING_DIR}
sync_repo_and_patch metal3-dev-env https://github.com/metal3-io/metal3-dev-env.git

VM_SETUP_PATH="${REPO_PATH}/metal3-dev-env/vm-setup"

ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "virthost=$HOSTNAME" \
  -i ${VM_SETUP_PATH}/inventory.ini \
  -b -vvv ${VM_SETUP_PATH}/install-package-playbook.yml
# Install oc client
oc_version=4.2
oc_tools_dir=$HOME/oc-${oc_version}
oc_tools_local_file=openshift-client-${oc_version}.tar.gz
oc_date=0
if which oc 2>&1 >/dev/null ; then
    oc_date=$(date -d $(oc version -o json  | jq -r '.clientVersion.buildDate') +%s)
fi
if [ ! -f ${oc_tools_dir}/${oc_tools_local_file} ] || [ $oc_date -lt 1566755586 ]; then
  mkdir -p ${oc_tools_dir}
  cd ${oc_tools_dir}
  wget https://mirror.openshift.com/pub/openshift-v4/clients/oc/${oc_version}/linux/oc.tar.gz -O ${oc_tools_local_file}
  tar xvzf ${oc_tools_local_file}
  sudo cp oc /usr/local/bin/
fi

# Install operator-sdk
if ! which operator-sdk 2>&1 >/dev/null ; then
    sudo wget https://github.com/operator-framework/operator-sdk/releases/download/v0.9.0/operator-sdk-v0.9.0-x86_64-linux-gnu -O /usr/local/bin/operator-sdk
    sudo chmod 755 /usr/local/bin/operator-sdk
fi

# Install Go dependency management tool
# Using pre-compiled binaries instead of installing from source
eval "$(go env)"
export PATH="${GOPATH}/bin:$PATH"
if ! which dep 2>&1 >/dev/null ; then
    mkdir -p $GOPATH/bin
    curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
fi
