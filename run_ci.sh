#!/bin/bash
set -ex

source common.sh

if [ -n "$PS1" ]; then
    echo "This script is for running dev-script in our CI env, it is tailored to a"
    echo "very specific setup and unlikely to be usefull outside of CI"
    exit 1
fi

# Display the "/" filesystem mounted incase we need artifacts from it after the job
mount | grep root-

# The CI host has a "/" filesystem that reset for each job, the only partition
# that persist is /opt (and /boot), we can use this to store data between jobs
FILECACHEDIR=/opt/data/filecache
FILESTOCACHE="/home/notstack/dev-scripts/$RHCOS_IMAGE_FILENAME /opt/dev-scripts/ironic/html/images/$RHCOS_IMAGE_FILENAME_OPENSTACK /opt/dev-scripts/ironic/html/images/ironic-python-agent.initramfs /opt/dev-scripts/ironic/html/images/ironic-python-agent.kernel"

# Point at our CI custom config file (contains the PULL_SECRET
export CONFIG=/opt/data/config_notstack.sh

# Because "/" is a btrfs subvolume snapshot and a new one is created for each CI job
# to prevent each snapshot taking up too much space we keep some of the larger files
# on /opt we need to delete these before the job starts
sudo rm -rf /opt/libvirt-images/* /opt/dev-scripts

# Populate some file from the cache so we don't need to download them
sudo mkdir -p $FILECACHEDIR
for FILE in $FILESTOCACHE ; do
    sudo mkdir -p $(dirname $FILE)
    [ -f $FILECACHEDIR/$(basename $FILE) ] && sudo cp $FILECACHEDIR/$(basename $FILE) $FILE
done
sudo chown -R notstack /opt/dev-scripts/ironic

# Run dev-scripts
make | sed -e 's/.*auth.*/*** PULL_SECRET ***/g'

# Populate cache for files it doesn't have
for FILE in $FILESTOCACHE ; do
    if [ ! -f $FILECACHEDIR/$(basename $FILE) ] ; then
        sudo cp $FILE $FILECACHEDIR/$(basename $FILE)
    fi
done
