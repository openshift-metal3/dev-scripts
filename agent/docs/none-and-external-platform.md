# None and External Platform Support

## Configuration Variable

To enable None platform for compact and HA clusters:
````
export AGENT_PLATFORM_TYPE=none
````
To enable External platform for SNO, compact, and HA clusters:
````
export AGENT_PLATFORM_TYPE=external
````

To enable OCI as an external platform for SNO, compact, and HA clusters:
````
export AGENT_PLATFORM_NAME=oci
````

### Network Configuration

With None and External platforms, the user is responsible for configuring the DNS entries for
the Kubernetes API, OpenShift application wildcard, and the names of the control plane
and compute machines. Users are also responsible for providing a load balancer
infrastructure for the API and application ingress. 

In the context of dev-scripts and excluding SNO, these platforms require the following DNS
records to be present in the 'ostestbm' network.
* api.<cluster_name>.<base_domain> 
* api-int.<cluster_name>.<base_domain> 'new'
* *.apps.<cluster_name>.<base_domain>. 'new'

All three names point to the load balancer's IP address. 

The DNS records are added to the ostestbm libvirt network by the enable_load_balancer()
function in 'agent/05_agent_configure.sh'.

````
sudo virsh net-dumpxml ostestbm
<network xmlns:dnsmasq='http://libvirt.org/schemas/network/dnsmasq/1.0'>
  <name>ostestbm</name>
  <uuid>f08b75ac-419e-4c0a-8889-45935533f2f6</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='ostestbm' stp='on' delay='0'/>
  <mac address='52:54:00:a4:61:9b'/>
  <domain name='ostest.test.metalkube.org' localOnly='yes'/>
  <dns>
    <forwarder domain='apps.ostest.test.metalkube.org' addr='127.0.0.1'/>
    <host ip='192.168.111.2'>
      <hostname>ns1</hostname>
    </host>
    <host ip='192.168.111.80'>
      <hostname>master-0</hostname>
    </host>
    <host ip='192.168.111.81'>
      <hostname>master-1</hostname>
    </host>
    <host ip='192.168.111.82'>
      <hostname>master-2</hostname>
    </host>
    <host ip='192.168.111.83'>
      <hostname>worker-0</hostname>
    </host>
    <host ip='192.168.111.84'>
      <hostname>worker-1</hostname>
    </host>
    <host ip='192.168.111.1'>
      <hostname>api</hostname>
      <hostname>api-int</hostname>
      <hostname>*.apps</hostname>
      <hostname>virthost</hostname>
    </host>
  </dns>
  ** snip **
  <dnsmasq:options>
    <dnsmasq:option value='cache-size=0'/>
  </dnsmasq:options>
</network>
````

'haproxy' is the load balancer deployed for enabling the None and External platforms with the agent-based installer.
The haproxy service is configured and enabled by the enable_load_balancer() function.

'haproxy' runs on the hypervisor host and is accessed by the hosts forming the OpenShift cluster through
the 'ostestbm' network's .1 or ::1 IP address.

Its configuration follows the sample load balancer configuration for user-provisioned clusters described in https://docs.openshift.com/container-platform/4.13/installing/installing_bare_metal/installing-bare-metal.html#installation-load-balancing-user-infra-example_installing-bare-metal.

The OpenShift services configured to use the external load balancer are:
* Kubernetes api port 6443
* Machine config server port 22623 - serves the ignition configs
* Ingress router ports 443 and 80

These ports are opened in the libvirt firewalld domain so that the VMs inside the domain can communicate with haproxy deployed
on the hypervisor host.

In '/etc/NetworkManager/dnsmasq.d/openshift-ostest.conf', api and .app addresses are updated to point to the load balancer IP.

For IPv4:

````
address=/api.ostest.test.metalkube.org/192.168.111.1
address=/.apps.ostest.test.metalkube.org/192.168.111.1
````

For IPv6:

````
address=/api.ostest.test.metalkube.org/fd2e:6f44:5dd8:c956::1
address=/.apps.ostest.test.metalkube.org/fd2e:6f44:5dd8:c956::1
````

This to ensure that any clients attempting to use the Kubernetes API from the hypervisor host can reach it.
For example, if the api IP address isn't updated and left pointing to the API_VIP used by the baremetal platform:

```
[rwsu@ dev-scripts]export KUBECONFIG=./ocp/ostest/auth/kubeconfig
[rwsu@ dev-scripts]$ oc get co
Unable to connect to the server: dial tcp 192.168.111.5:6443: connect: no route to host
```

