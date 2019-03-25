#!/bin/bash

# Ensure we arn't mentioning the provisioning interface is the kernel
# command line, doing so stalls dracut if dhcp isn't available on it
sudo sed --follow-symlinks -i.old -e "s/ ip=eth0:dhcp//g" /boot/grub2/grub.cfg
sudo sed --follow-symlinks -i.old -e 's/ip=eth0:dhcp/ip=eth1:dhcp/g' /etc/default/grub
sync
