#!/bin/bash

# FIXME(lranjbar): Look into a cleaner way to do this
# Attach the fleeting.iso to the VM and start it
virsh attach-disk ${CLUSTER_NAME}_fleeting_0 ${FLEETING_ISO_LOCATION} hdc --type cdrom --mode readonly
virsh start ${CLUSTER_NAME}_fleeting_0 --force-boot
