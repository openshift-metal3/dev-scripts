#!/bin/bash
set -ex

if [ -n "$PS1" ]; then
    echo "This script is for running dev-script in our CI env, it is tailored to a"
    echo "very specific setup and unlikely to be usefull outside of CI"
    exit 1
fi

# Display the "/" filesystem mounted incase we need artifacts from it after the job
mount | grep root-

# Point at our CI custom config file (contains the PULL_SECRET
export CONFIG=/opt/data/config_notstack.sh

# Because "/" is a btrfs subvolume snapshot and a new one is created for each CI job
# to prevent each snapshot taking up too much space we keep some of the larger files
# on /opt we need to delete these before the job starts
sudo rm -rf /opt/libvirt-images/* /opt/dev-scripts

# Run dev-scripts
make | sed -e 's/.*auth.*/*** PULL_SECRET ***/g'
