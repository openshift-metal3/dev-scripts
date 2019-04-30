#!/usr/bin/bash

set -eux

figlet "Deploying nfs" | lolcat

sudo yum -y install nfs-utils
sudo mkdir /windows
grep -q /windows /etc/exports || sudo bash -c "echo /windows *\(rw,no_root_squash\)  >> /etc/exports"
sudo chcon -t svirt_sandbox_file_t /windows
sudo chmod 777 /windows
sudo exportfs -r
sudo systemctl start nfs ; sudo systemctl enable nfs-server
#Allow access to nfs
for port in 111 2049 20048 ; do
    if ! sudo iptables -C INPUT -i baremetal -p udp --dport $port -j ACCEPT 2>/dev/null ; then
        sudo iptables -I INPUT -i baremetal -p udp --dport $port -j ACCEPT
    fi
    if ! sudo iptables -C INPUT -i baremetal -p tcp --dport $port -j ACCEPT 2>/dev/null ; then
        sudo iptables -I INPUT -i baremetal -p tcp --dport $port -j ACCEPT
    fi
done

sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload
