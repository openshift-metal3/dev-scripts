#!/bin/bash
# This script configures xinetd
# Script steps:
# 1. Install xinetd
# 2. Copy the example config file
# 3. Edit the config file
# 4. Restart xinetd
# 5. Open ports 443 and 6443
# 6. Display values for the local machine's /etc/hosts

# Install
sudo yum install xinetd -y
# Copy the config file
if [ ! -f "/etc/xinetd.d/openshift" ]; then
    sudo cp dev-scripts/openshift_xinetd_example.conf /etc/xinetd.d/openshift
fi
# Get the IP values
addrs=$(cat dev-scripts/ocp/ostest/.openshift_install_state.json | jq '.["*installconfig.InstallConfig"]["config"]["platform"]["baremetal"] | .apiVIP, .ingressVIP')
apivip=$(echo $addrs | sed '1!d')
ingressvip=$(echo $addrs | sed '2!d')
# Replace values
sed -i "s/<IPv6_API_Address>/${apivip}/g; s/<IPv6_Ingress_Address>/${apivip}/g" /etc/xinetd.d/openshift
# Restart
sudo systemctl restart xinetd
# Firewall
sudo firewall-cmd --zone=public --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --reload
# Hosts file values
ip_address=$(ifconfig eno2 | grep inet | sed 's/^ *//g; 1!d' | cut -d " " -f 2)
if [ -z "$ip_address" ]; then
    $ip_address="<HOST_IP>"
fi
echo "Populate your local machine's /etc/hosts file with:"
echo "${ip_address} console-openshift-console.apps.ostest.test.metalkube.org openshift-authentication-openshift-authentication.apps.ostest.test.metalkube.org grafana-openshift-monitoring.apps.ostest.test.metalkube.org prometheus-k8s-openshift-monitoring.apps.ostest.test.metalkube.org api.ostest.test.metalkube.org oauth-openshift.apps.ostest.test.metalkube.org"
