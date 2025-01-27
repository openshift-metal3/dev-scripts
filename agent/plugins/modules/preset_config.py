#!/usr/bin/python

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = r'''
---
module: preset_config
version_added: "0.0.1"
short_description: Set the environment variables to the default values in openshift-metal3/dev-scripts.
description:
    - Set the environment variables for baremetal testing with openshift-metal3/dev-scripts.

options:
    ci_token:
        description: CI_TOKEN to use when running dev-scripts.
        default: null
        required: true
        type: str
    working_dir:
        description: WORKING_DIR to use when running dev-scripts.
        default: /opt/dev-scripts
        type: str
    openshift_release_stream:
        description: Openshift release stream to install.
        default: 4.11
        type: str
    openshift_release_type:
        description: Openshift release type to install.
        choices: ci, nightly, ga
        type: str
    openshift_version:
        description: Openshift release version to install. This version should be in the above release stream.
        default: If unset this is the same value as openshift_release_stream
        type: str
    cluster_name:
        description: Name of the Openshift cluster created.
        default: ostest
        type: str
    base_domain:
        description: Base DNS domain of the Openshift cluster created.
        default: test.metalkube.org
        type: str
    cluster_topology:
        description: Cluster topology defines the number cluster nodes.
        default: ha
        choices: ['ha', 'compact', 'sno', 'arbiter']
        type: str
    resource_profile:
        description: Resource profile controls resource size of each node.
        default: minimal
        choices: ['minimal', 'recommended']
        type: str
    extra_workers_profile:
        description: Create extra workers for the cluster. Useful for day2 operations.
        default: none
        choices: ['none', 'day2active', 'day2inactive']
        type: str
    ip_stack:
        description: IP stack of the Openshift cluster
        default: v4
        choices: ['v4', 'v6', 'v4v6']
        type: str
    host_ip_stack:
        description: External host IP stack of the Openshift cluster
        default: v4
        choices: ['v4', 'v6', 'v4v6']
        type: str
    provisioning_network_profile:
        description: Whether or not the Openshift cluster provisioning network is disabled
        default: Managed
        choices: ['Managed','Disabled']
        type: str
    agent_static_ip_node0_only:
        description: True if only node0 has a static IP.
        type: str
author:
    - Lisa Ranjbar (@lranjbar)
'''

from ansible.module_utils.basic import AnsibleModule
from getpass import getuser
from pathlib import Path
from os.path import exists

facts_base = {}
facts_cluster = {}
facts_network = {}
facts_agent = {}

def main():
    module = AnsibleModule(
        argument_spec=dict(
            ci_token=dict(type='str', required=True),
            ci_server=dict(type='str', default='api.ci.l2s4.p1.openshiftapps.com'),
            working_dir=dict(type='str', default='/opt/dev-scripts'),
            openshift_release_stream=dict(type='str', default='4.11'),
            openshift_release_type=dict(type='str', default='nightly', choices=['ci', 'nightly', 'ga']),
            openshift_version=dict(type='str'),
            cluster_name=dict(type='str', default='ostest'),
            base_domain=dict(type='str', default='test.metalkube.org'),
            cluster_topology=dict(type='str', default='ha', choices=['ha', 'compact', 'sno', 'arbiter']),
            resource_profile=dict(type='str', default='minimal', choices=['minimal', 'recommended']),
            extra_workers_profile=dict(type='str', default='none', choices=['none', 'day2active', 'day2inactive']),
            ip_stack=dict(type='str', default='v6', choices=['v4', 'v6', 'v4v6']),
            host_ip_stack=dict(type='str', choices=['v4', 'v6', 'v4v6']),
            provisioning_network_profile=dict(type='str', default='Managed', choices=['Managed','Disabled']),
            agent_static_ip_node0_only=dict(type='bool', default=False)
    ),
        supports_check_mode=True
    )

    result = dict(
        changed=False,
        ansible_facts=dict(
            devscripts=dict(
                ci_token=None, ci_server=None, working_dir=None, script_dir=None,
                openshift_releaes_stream=None, openshift_release_type=None, openshift_version=None,
                cluster_name=None, base_domain=None, cluster_domain=None, ocp_dir=None,
                provisioning_host_user=None, provisioning_network_name=None, baremetal_network_name=None,
                local_registry_dns_name=None, registry_dir=None, registry_creds=None,
                mirror_log_file=None,
                cluster_topology=None,resource_profile=None,extra_workers_profile=None,
                num_masters=None,num_workers=None,num_extra_workers=None,
                master_memory=None,master_disk=None,master_vcpu=None,
                worker_memory=None,worker_disk=None,worker_vcpu=None,
                extra_worker_memory=None,extra_worker_disk=None,extra_worker_vcpu=None,
                apply_extra_workers=None,
                ip_stack=None,host_ip_stack=None,network_type=None,
                cluster_subnet_v4=None,cluster_host_prefix_v4=None,service_subnet_v4=None,
                cluster_subnet_v6=None,cluster_host_prefix_v6=None,service_subnet_v6=None,
                cluster_network=None, cluster_host_prefix=None, service_network=None,
                provisioning_network=None,external_subnet_v4=None,external_subnet_v6=None,
                external_network=None,
                provisioning_ip_subnet=None, mirror_images=None,
                agent_static_ip_node0_only=None
            )
        )
    )

    home_dir = str(Path.home())
    ssh_pub_key_file = home_dir+"/.ssh/id_rsa.pub"
    pull_secret_file = module.params['working_dir']+"/pull_secret.json"

    if not exists(ssh_pub_key_file):
        module.fail_json(msg="Unable to find ssh pub key file.", **result)

    if not exists(pull_secret_file):
        module.fail_json(msg="Unable to find pull secret file.", **result)

    facts_base = generate_preset_base(
        home_dir=home_dir,
        ssh_pub_key_file=ssh_pub_key_file,
        pull_secret_file=pull_secret_file,
        ci_token=module.params['ci_token'],
        ci_server=module.params['ci_server'],
        working_dir=module.params['working_dir'],
        openshift_release_stream=module.params['openshift_release_stream'],
        openshift_release_type=module.params['openshift_release_type'],
        openshift_version=module.params['openshift_version'],
        cluster_name=module.params['cluster_name'],
        base_domain=module.params['base_domain']
    )

    facts_cluster = determine_cluster_topology(
        cluster_topology=module.params['cluster_topology'],
        resource_profile=module.params['resource_profile'],
        extra_workers_profile=module.params['extra_workers_profile']
    )

    facts_network = determine_network_topology(
        ip_stack=module.params['ip_stack'],
        host_ip_stack=module.params['host_ip_stack'],
        provisioning_network_profile=module.params['provisioning_network_profile']
    )

    facts_agent = generate_preset_agent(
        agent_static_ip_node0_only=module.params['agent_static_ip_node0_only']
    )

    facts = {**facts_base, **facts_cluster, **facts_network, **facts_agent}

    if module.check_mode:
        module.exit_json(**result)

    result['ansible_facts']['devscripts'] = facts
    module.exit_json(**result)

def generate_preset_base(home_dir, ci_token, ci_server, working_dir, ssh_pub_key_file, pull_secret_file,
                        openshift_release_stream, openshift_release_type, openshift_version,
                        cluster_name, base_domain):

    cluster_domain = cluster_name+"."+base_domain
    ocp_dir = working_dir+"/ocp/"+cluster_name
    manifests_dir = ocp_dir+"/cluster-manifests"
    provisioning_host_user = getuser()
    provisioning_network_name = cluster_name+"pr"
    baremetal_network_name = cluster_name+"bm"
    local_registry_dns_name = "virthost."+cluster_name+"."+base_domain
    registry_dir = working_dir+"/registry"
    registry_creds = home_dir+"/private-mirror-"+cluster_name+".json"
    mirror_log_file = registry_dir+"/"+cluster_name+"-image_mirror-"+openshift_release_stream+"-"+openshift_release_type+".log"

    if openshift_version is None:
        openshift_version = openshift_release_stream

    facts = {
        'ci_token': ci_token,
        'ci_server': ci_server,
        'working_dir': working_dir,
        'home_dir': home_dir,
        'pull_secret_file': pull_secret_file,
        'ssh_pub_key_file': ssh_pub_key_file,
        'openshift_release_stream': openshift_release_stream,
        'openshift_release_type': openshift_release_type,
        'openshift_version': openshift_version,
        'cluster_name': cluster_name,
        'base_domain': base_domain,
        'cluster_domain': cluster_domain,
        'ocp_dir': ocp_dir,
        'manifests_dir': manifests_dir,
        'provisioning_host_user': provisioning_host_user,
        'provisioning_network_name': provisioning_network_name,
        'baremetal_network_name': baremetal_network_name,
        'local_registry_dns_name': local_registry_dns_name,
        'registry_dir': registry_dir,
        'registry_creds': registry_creds,
        'mirror_log_file': mirror_log_file
    }

    return facts

def determine_cluster_topology(cluster_topology, resource_profile, extra_workers_profile):
    num_masters, num_arbiters, num_workers, num_extra_workers = 0, 0, 0, 0
    master_memory, master_disk, master_vcpu = None, None, None
    arbiter_memory, arbiter_disk, arbiter_vcpu = None, None, None
    worker_memory, worker_disk, worker_vcpu = None, None, None
    extra_worker_memory, extra_worker_disk, extra_worker_vcpu = None, None, None
    apply_extra_workers = None
    node_hostname_static_ip = []

    # Define the number of nodes based off topology
    if cluster_topology == 'ha':
        num_masters, num_arbiters, num_workers = 3, 0, 2
    elif cluster_topology == 'compact':
        num_masters, num_arbiters, num_workers = 3, 0, 0
    elif cluster_topology == 'arbiter':
        num_masters, num_arbiters, num_workers = 2, 1, 0
    elif cluster_topology == 'sno':
        num_masters, num_arbiters, num_workers = 1, 0, 0

    if extra_workers_profile == 'none':
        num_extra_workers, apply_extra_workers = 0, None
    elif extra_workers_profile == 'day2inactive':
        num_extra_workers, apply_extra_workers = 1, False
    elif extra_workers_profile == 'day2active':
        num_extra_workers, apply_extra_workers = 1, True

    # Define the master node resources
    if num_masters > 0:
        # SNO topology uses one "large" master node
        if cluster_topology == 'sno':
            if resource_profile == 'minimal':
                master_memory, master_disk, master_vcpu = '16384', '20', '4'
            elif resource_profile == 'recommended':
                master_memory, master_disk, master_vcpu = '32768', '120', '8'
            else:
                pass

        # Other toplogies use mulitple master nodes
        else:
            if resource_profile == 'minimal':
                master_memory, master_disk, master_vcpu = '16384', '20', '4'
            elif resource_profile == 'recommended':
                master_memory, master_disk, master_vcpu = '16384', '120', '8'
            else:
                pass
    # Define the worker node resources
    if num_arbiters > 0:
        cluster_topology = 'arbiter'
        if resource_profile == 'minimal':
            arbiter_memory, arbiter_disk, arbiter_vcpu = '8192', '20', '2'
        elif resource_profile == 'recommended':
            arbiter_memory, arbiter_disk, arbiter_vcpu = '16384', '120', '4'
        else:
            pass

    # Define the worker node resources
    if num_workers > 0:
        if resource_profile == 'minimal':
            worker_memory, worker_disk, worker_vcpu = '8192', '20', '2'
        elif resource_profile == 'recommended':
            worker_memory, worker_disk, worker_vcpu = '16384', '120', '4'
        else:
            pass

    # Define the extra worker node resources
    if num_extra_workers > 0:
        if resource_profile == 'minimal':
            extra_worker_memory, extra_worker_disk, extra_worker_vcpu = '8192', '20', '2'
        elif resource_profile == 'recommended':
            extra_worker_memory, extra_worker_disk, extra_worker_vcpu = '16384', '120', '4'
        else:
            pass

    facts = {
        'cluster_topology': cluster_topology,
        'resource_profile': resource_profile,
        'extra_workers_profile': extra_workers_profile,
        'num_masters': str(num_masters),
        'num_workers': str(num_workers),
        'num_extra_workers': str(num_extra_workers),
        'master_memory': master_memory,
        'master_disk': master_disk,
        'master_vcpu': master_vcpu,
        'num_arbiters': str(num_arbiters),
        'arbiter_memory': arbiter_memory,
        'arbiter_disk': arbiter_disk,
        'arbiter_vcpu': arbiter_vcpu,
        'worker_memory': worker_memory,
        'worker_disk': worker_disk,
        'worker_vcpu': worker_vcpu,
        'extra_worker_memory': extra_worker_memory,
        'extra_worker_disk': extra_worker_disk,
        'extra_worker_vcpu': extra_worker_vcpu,
        'apply_extra_workers': apply_extra_workers,
    }

    return facts

def determine_network_topology(ip_stack='v4', host_ip_stack=None, provisioning_network_profile='Managed'):
    network_type = None
    cluster_subnet_v4, cluster_host_prefix_v4, service_subnet_v4 = None, None, None
    cluster_subnet_v6, cluster_host_prefix_v6, service_subnet_v6 = None, None, None
    cluster_network, cluster_host_prefix, service_network = None, None, None
    provisioning_network, external_subnet_v4, external_subnet_v6 = None, None, None
    external_network = None
    provisioning_ip_subnet, mirror_images = None, None

    if host_ip_stack == None:
        host_ip_stack = ip_stack

    if host_ip_stack == 'v4':
        provisioning_network, external_subnet_v4, external_subnet_v6 = "172.22.0.0/24", "192.168.111.0/24", ""
        external_network = external_subnet_v4
    elif host_ip_stack == 'v6':
        provisioning_network, external_subnet_v4, external_subnet_v6 = "fd00:1101::0/64", "", "fd2e:6f44:5dd8:c956::/120"
        external_network = external_subnet_v6
    elif host_ip_stack == 'v4v6':
        provisioning_network, external_subnet_v4, external_subnet_v6 = "fd00:1101::0/64", "192.168.111.0/24", "fd2e:6f44:5dd8:c956::/120"
        external_network = external_subnet_v6
    else:
        pass

    if ip_stack == 'v4':
        network_type = "OpenShiftSDN"
        cluster_subnet_v4, cluster_host_prefix_v4, service_subnet_v4 = "10.128.0.0/14", "23", "172.30.0.0/16"
        cluster_subnet_v6, cluster_host_prefix_v6, service_subnet_v6 = "", "", ""
        cluster_network, cluster_host_prefix, service_network = cluster_subnet_v4, cluster_host_prefix_v4, service_subnet_v4
    elif ip_stack == 'v6':
        network_type = "OVNKubernetes"
        cluster_subnet_v4, cluster_host_prefix_v4, service_subnet_v4 = "", "", ""
        cluster_subnet_v6, cluster_host_prefix_v6, service_subnet_v6 = "fd01::/48", "64", "fd02::/112"
        cluster_network, cluster_host_prefix, service_network = cluster_subnet_v6, cluster_host_prefix_v6, service_subnet_v6
        mirror_images = True
    elif ip_stack == 'v4v6':
        network_type = "OVNKubernetes"
        cluster_subnet_v4, cluster_host_prefix_v4, service_subnet_v4 = "10.128.0.0/14", "23", "172.30.0.0/16"
        cluster_subnet_v6, cluster_host_prefix_v6, service_subnet_v6 = "fd01::/48", "64", "fd02::/112"
        cluster_network, cluster_host_prefix, service_network = cluster_subnet_v4, cluster_host_prefix_v4, service_subnet_v4
    else:
        pass

    if provisioning_network_profile == 'Disabled':
        if host_ip_stack == 'v6':
            provisioning_ip_subnet = external_subnet_v6
        else:
            provisioning_ip_subnet = external_subnet_v4

    facts = {
        'ip_stack': ip_stack,
        'host_ip_stack': host_ip_stack,
        'network_type': network_type,
        'cluster_subnet_v4': cluster_subnet_v4,
        'cluster_host_prefix_v4': cluster_host_prefix_v4,
        'service_subnet_v4': service_subnet_v4,
        'cluster_subnet_v6': cluster_subnet_v6,
        'cluster_host_prefix_v6': cluster_host_prefix_v6,
        'service_subnet_v6': service_subnet_v6,
        'cluster_network': cluster_network,
        'cluster_host_prefix': cluster_host_prefix,
        'service_network': service_network,
        'provisioning_network': provisioning_network,
        'external_subnet_v4': external_subnet_v4,
        'external_subnet_v6': external_subnet_v6,
        'external_network': external_network,
        'provisioning_network_profile': provisioning_network_profile,
        'provisioning_ip_subnet': provisioning_ip_subnet,
        'mirror_images': mirror_images,
        'base_static_ip': '80'
    }

    return facts

def generate_preset_agent(agent_static_ip_node0_only):

    facts = {
        'agent_static_ip_node0_only': agent_static_ip_node0_only
    }

    return facts


if __name__ == '__main__':
    main()