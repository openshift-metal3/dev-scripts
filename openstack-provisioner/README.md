Running installer dev scripts on an OpenStack environment
=========================================================

This document describes how to get the developer scripts running on top of an
OpenStack deployment.

# Test environment infrastructure

We use [linchpin](https://github.com/CentOS-PaaS-SIG/linchpin) for provisioning
the test infrastructure components and a post deployment Ansible hook for running
extra configuration such as:
 - disabling the port security for the rhhi.next networks ports
 - setting up an external DNS and DHCP server
 - [OVB](https://github.com/openstack/openstack-virtual-baremetal) server configuration
   for IPMI protocol emulation of the OpenShift instances
 - trigerring dev-scripts

The topology includes the following OpenStack instances:

`provisioninghost`
 - acting as the provisioning host running dev-scripts
 - note: the bootstrap VM will run as an L2 nested VM

`routerbmc`
 - external router running DNS and DHCP services
 - running OVB service

`master-{0..2}`
 - production cluster OpenShift nodes

And the following networks:

`management`
 - used for Ansible SSH access. Only routerbmc and provisioninghost
     instances are connected to this network.

`baremetal`
 - public traffic used for API access to deployed OCP and application traffic

`provisioning`
 - PXE/DHCP traffic used for Ironic nodes provisioning

![alt text](https://raw.githubusercontent.com/mcornea/metalkube-dev-scripts-openstack/master/rhhi-openstack.png)

# Pre-requisites

 - OpenStack client config file with correct credentials in ~/.config/openstack/clouds.yaml
```yaml
clouds:
 rdocloud:
    auth:
        auth-url: https://example.com:13000/v3
        password: password
        project-name: project
        project_domain_name: default
        user_domain_name: Default
        username: username
    identity_api_version: '3'
```

 - Linchpin installation
```bash
git clone https://github.com/CentOS-PaaS-SIG/linchpin.git
cd linchpin
# create and activate python virtual env
virtualenv --python=/usr/bin/python2.7 .venv
source .venv/bin/activate
# install linchpin and openstackclient
pip install -v . python-openstackclient
# Fix libselinux-python libraries path
# https://linchpin.readthedocs.io/en/latest/installation.html?highlight=selinux#virtual-environments-and-selinux
./scripts/install_selinux_venv.sh
```

# Instructions

- Clone dev-scripts repository:
  - `git clone https://github.com/metalkube/dev-scripts.git`

- Go to the openstack-provisioner linchpin workspace:
  - `cd dev-scripts/openstack-provisioner/`

- Edit vars in `hooks/ansible/post/extravars.yml`:
  - `test_os_client_config`: OpenStack client config file location
  - `test_os_client_profile`: Profile from client config file to be used
  - `test_os_keypair`: Key Pair name to be assigned to instances
  - `test_os_image`: Image to be used for provisioninghost and routerbmc instances
  - `test_os_image_ipxe`: Image to be used for pxe booting
  - `test_os_provisionhost_flavor`: Flavor to be used for provisioninghost instance
  - `test_os_master_flavor`: Flavor to be used for OpenShift master instances
  - `test_os_routerbmc_flavor`: Flavor to be used for routerbmc instance
  - `test_os_floating_ip_net`: Name of network used for floating IPs access
  - `openshift_secret`: OpenShift pull secret

- Clean up any preexisting deployments:
  - `linchpin --template-data @hooks/ansible/post/extravars.yml -v destroy`

- Run deployment
  - `linchpin --template-data @hooks/ansible/post/extravars.yml -v up`
