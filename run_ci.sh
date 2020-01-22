#!/bin/bash
set -ex

# grabs files and puts them into $LOGDIR to be saved as jenkins artifacts
function getlogs(){
    LOGDIR=/home/notstack/dev-scripts/logs

    # Grab the host journal
    sudo journalctl > $LOGDIR/bootstrap-host-system.journal

    for c in httpd machine-os-downloader ipa-downloader ; do
        sudo podman logs $c > $LOGDIR/$c.log || true
    done

    # And the VM journals and staticpod container logs
    for HOST in $(sudo virsh net-dhcp-leases baremetal | grep -o '192.168.111.[0-9]\+') ; do
        sshpass -p notworking $SSH core@$HOST sudo journalctl > $LOGDIR/$HOST-system.journal || true
        sshpass -p notworking $SSH core@$HOST sudo journalctl -u ironic.service > $LOGDIR/$HOST-ironic.journal || true
	for c in $(sshpass -p notworking $SSH core@$HOST sudo podman ps -a | grep -e ironic -e downloader -e httpd -e dnsmasq -e mariadb | awk '{print $NF}'); do
		sshpass -p notworking $SSH core@$HOST sudo podman logs $c > $LOGDIR/${HOST}-${c}-container.log || true
	done
    done

    # openshift info
    export KUBECONFIG=ocp/auth/kubeconfig
    oc --request-timeout=5s get clusterversion/version > $LOGDIR/cluster_version.log || true
    oc --request-timeout=5s get clusteroperators > $LOGDIR/cluster_operators.log || true
    oc --request-timeout=5s get pods --all-namespaces | grep -v Running | grep -v Completed  > $LOGDIR/failing_pods.log || true

    # Baremetal Operator info
    mkdir -p $LOGDIR/baremetal-operator
    BMO_POD=$(oc --request-timeout=5s get pods --namespace openshift-machine-api | grep metal3 | awk '{print $1}')
    BMO_CONTAINERS=$(oc --request-timeout=5s get pods ${BMO_POD} -n openshift-machine-api -o jsonpath="{.spec['containers','initContainers'][*].name}")
    for c in ${BMO_CONTAINERS}; do
        oc --request-timeout=5s logs ${BMO_POD} -c ${c} --namespace openshift-machine-api > $LOGDIR/baremetal-operator/${c}.log
    done
}
trap getlogs EXIT

# Point at our CI custom config file (contains the PULL_SECRET)
export CONFIG=/opt/data/config_notstack.sh

# Install moreutils for ts
sudo yum install -y epel-release
sudo yum install -y moreutils
# Install jq and golang for common.sh
sudo yum install -y jq golang
sudo yum remove -y epel-release

# Clone the project being tested, "dev-scripts" will have been cloned in the jenkins
# job definition, for all others we do it here
if [ -n "$REPO" -a -n "$BRANCH" ]  ; then
    pushd ~
    if [ ! -d ${BASE_REPO#*/} ] ; then
        git clone https://github.com/$BASE_REPO -b ${BASE_BRANCH:-master}
        cd ${BASE_REPO#*/}
        git pull --no-edit  https://github.com/$REPO $BRANCH
        git log --oneline -10 --graph
    fi
    popd
fi

# Project-specific actions. If these directories exist in $HOME, move
# them to the correct $GOPATH locations.
for PROJ in installer ; do
    [ ! -d /home/notstack/$PROJ ] && continue

    if [ "$PROJ" == "installer" ]; then
      export KNI_INSTALL_FROM_GIT=true
    fi

    # Set origin so that sync_repo_and_patch is rebasing against the correct source
    cd /home/notstack/$PROJ
    git branch -M master
    git remote set-url origin https://github.com/$BASE_REPO
    cd -

    mkdir -p $HOME/go/src/github.com/${BASE_REPO/\/*}
    mv /home/notstack/$PROJ $HOME/go/src/github.com/$BASE_REPO
done

# If directories for the containers exists then we build the images (as they are what triggered the job)
if [ -d "/home/notstack/ironic-image" ] ; then
    export IRONIC_LOCAL_IMAGE=https://github.com/metal3-io/ironic-image
    export UPSTREAM_IRONIC=true
fi
if [ -d "/home/notstack/ironic-inspector-image" ] ; then
    export IRONIC_INSPECTOR_LOCAL_IMAGE=https://github.com/metal3-io/ironic-inspector-image
    export UPSTREAM_IRONIC=true
fi
if [ -d "/home/notstack/baremetal-runtimecfg" ] ; then
    export BAREMETAL_RUNTIMECFG_LOCAL_IMAGE=https://github.com/openshift/baremetal-runtimecfg
fi
if [ -d "/home/notstack/mdns-publisher" ] ; then
    export MDNS_PUBLISHER_LOCAL_IMAGE=https://github.com/openshift/mdns-publisher
fi

# Some of the setup done above needs to be done before we source common.sh
# in order for correct defaults to be set
source common.sh

if [ -n "$PS1" ]; then
    echo "This script is for running dev-script in our CI env, it is tailored to a"
    echo "very specific setup and unlikely to be usefull outside of CI"
    exit 1
fi

# Display the "/" filesystem mounted incase we need artifacts from it after the job
mount | grep root-

# $WORKING_DIR is on a BTRFS filesystem, we need to disable COW so VM images
# don't eat up all of the disk space
sudo chattr +C "$WORKING_DIR"

# The CI host has a "/" filesystem that reset for each job, the only partition
# that persist is /opt (and /boot), we can use this to store data between jobs
FILECACHEDIR=/opt/data/filecache
FILESTOCACHE="/opt/dev-scripts/ironic/html/images/ironic-python-agent.initramfs /opt/dev-scripts/ironic/html/images/ironic-python-agent.kernel"

# Because "/" is a btrfs subvolume snapshot and a new one is created for each CI job
# to prevent each snapshot taking up too much space we keep some of the larger files
# on /opt we need to delete these before the job starts
sudo find /opt/libvirt-images /opt/dev-scripts -mindepth 1 -maxdepth 1 -exec rm -rf {} \;

# Populate some file from the cache so we don't need to download them
sudo mkdir -p $FILECACHEDIR
for FILE in $FILESTOCACHE ; do
    sudo mkdir -p $(dirname $FILE)
    [ -f $FILECACHEDIR/$(basename $FILE) ] && sudo cp -p $FILECACHEDIR/$(basename $FILE) $FILE
done

sudo mkdir -p /opt/data/yumcache /opt/data/installer-cache /home/notstack/.cache/openshift-install/libvirt
sudo chown -R notstack /opt/dev-scripts/ironic /opt/data/installer-cache /home/notstack/.cache

# Make yum store its cache on /opt so packages don't need to be downloaded for each job
sudo sed -i -e '/keepcache=0/d' /etc/yum.conf
sudo mount -o bind /opt/data/yumcache /var/cache/yum

# Mount the openshift-installer cache directory so we don't download a Machine OS image for each run
sudo mount -o bind /opt/data/installer-cache /home/notstack/.cache/openshift-install/libvirt

# Install terraform
if [ ! -f /usr/local/bin/terraform ]; then
    sudo yum install -y unzip
    curl -O https://releases.hashicorp.com/terraform/0.12.2/terraform_0.12.2_linux_amd64.zip
    unzip terraform_*.zip
    sudo install terraform /usr/local/bin
    rm -f terraform_*.zip terraform
fi

# Run dev-scripts
set -o pipefail
timeout -s 9 105m make |& ts "%b %d %H:%M:%S | " |& sed -e 's/.*auths.*/*** PULL_SECRET ***/g'

# Deployment is complete, but now wait to ensure the worker node comes up.
export KUBECONFIG=ocp/auth/kubeconfig

wait_for_worker() {
    worker=$1
    echo "Waiting for worker $worker to appear ..."
    while [ "$(oc get nodes | grep $worker)" = "" ]; do sleep 5; done
    TIMEOUT_MINUTES=15
    echo "$worker registered, waiting $TIMEOUT_MINUTES minutes for Ready condition ..."
    oc wait node/$worker --for=condition=Ready --timeout=$[${TIMEOUT_MINUTES} * 60]s
}
wait_for_worker worker-0

# Populate cache for files it doesn't have, or that have changed
for FILE in $FILESTOCACHE ; do
    cached=$FILECACHEDIR/$(basename $FILE)
    current_hash=$(md5sum $FILE | cut -f1 -d' ')
    if [ -f $cached ]; then
      cached_hash=$(md5sum $cached | cut -f1 -d' ')
    fi

    if [ ! -f $cached ] || [ x"$current_hash" != x"$cached_hash" ] ; then
        sudo cp -p $FILE $cached
    fi
done
