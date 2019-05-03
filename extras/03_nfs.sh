#!/usr/bin/bash

set -eux

figlet "Deploying nfs" | lolcat

sudo yum -y install nfs-utils
sudo [ -d "/windows" ] || sudo mkdir /windows
grep -q /windows /etc/exports || sudo bash -c "echo /windows *\(rw,no_root_squash\)  >> /etc/exports"
sudo chcon -t svirt_sandbox_file_t /windows
sudo chmod 777 /windows
sudo exportfs -r
sudo systemctl start nfs ; sudo systemctl enable nfs-server
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
