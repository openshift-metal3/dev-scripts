#!/bin/bash

PROVDEV=$(ip route get to 172.22.0.1 | awk '/dev/{print $3}')
sudo sed -i.old -e "s/ ip=${PROVDEV}:dhcp//g" /boot/grub2/grub.cfg
sync
