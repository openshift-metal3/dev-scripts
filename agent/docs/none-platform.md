# None Platform Support

## Configuration Variable

To enable None platform for compact and HA clusters:
````
export AGENT_PLATFORM_TYPE=none
````

### Network Configuration

With None platform, the user is responsible for configuring the DNS entries for
the Kubernetes API, OpenShift application wildcard, and the names of the control plane
and compute machines. Users are also responsible for providing a load balancer
infrastructure for the API and application ingress. 

In the context of dev-scripts, None platform requires these DNS records to be 
present in the 'ostestbm' network.
* api.<cluster_name>.<base_domain> 
* api-int.<cluster_name>.<base_domain> 'new'
* *.apps.<cluster_name>.<base_domain>. 'new'

All three names point to the load balancer's IP address. 

The DNS records are add to the ostestbm libvirt network by the enable_load_balancer() 
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

'haproxy' is the load balancer deployed for enabling the None platform with the agent-based installer. The haproxy service
is configured and enabled by the enable_load_balancer() function.

'haproxy' runs on the hypervisor host and is accessed by the hosts forming the OpenShift cluster through
the 'ostestbm' network through that network's .1 or ::1 IP address. Its configuration file path is /etc/haproxy/haproxy.cfg.
'haproxy' needs to be able to resolve the hostnames listed in its configuration file. Example of hostnames that need
to be resolvable on the hypervisor host:

````
listen api-server-6443
  bind *:6443
  mode tcp
  server master-0 master-0.ostest.test.metalkube.org:6443 check inter 1s
  server master-1 master-1.ostest.test.metalkube.org:6443 check inter 1s
  server master-2 master-2.ostest.test.metalkube.org:6443 check inter 1s
````

From the hypervisor host, hostnames such as master-0.ostest.test.metalkube.org are not resolvable by default.
To make them resolvable, the dnsmasq service on the hypervisor was updated.

An address entry for each host in the cluster has been updated in '/etc/NetworkManager/dnsmasq.d/openshift-ostest.conf':

address=/master-0.ostest.test.metalkube.org/192.168.111.80
address=/master-1.ostest.test.metalkube.org/192.168.111.81
address=/master-2.ostest.test.metalkube.org/192.168.111.82
address=/worker-0.ostest.test.metalkube.org/192.168.111.83
address=/worker-1.ostest.test.metalkube.org/192.168.111.84

In openshift-ostest.conf, api and .app addresses are also updated to point to the load balancer IP.
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



