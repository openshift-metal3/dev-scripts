from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import pytest
from unittest import TestCase
import ansible_collections.devscripts.agente2e.plugins.modules.preset_config as preset

@pytest.mark.parametrize(
    "test_input,expected",
    [
        (
            {'cluster_topology': 'ha', 'resource_profile': 'minimal','extra_workers_profile': 'none'},
            {'cluster_topology': 'ha', 'resource_profile': 'minimal', 'extra_workers_profile': 'none',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': '8192', 'worker_disk': '20', 'worker_vcpu': '2',
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None}
        ),
        (
            {'cluster_topology': 'ha', 'resource_profile': 'minimal','extra_workers_profile': 'day2inactive'},
            {'cluster_topology': 'ha', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2inactive',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': '8192', 'worker_disk': '20', 'worker_vcpu': '2',
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': False}
        ),
        (
            {'cluster_topology': 'ha', 'resource_profile': 'minimal','extra_workers_profile': 'day2active'},
            {'cluster_topology': 'ha', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2active',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': '8192', 'worker_disk': '20', 'worker_vcpu': '2',
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': True}
        ),
        (
            {'cluster_topology': 'ha', 'resource_profile': 'recommended','extra_workers_profile': 'none'},
            {'cluster_topology': 'ha', 'resource_profile': 'recommended', 'extra_workers_profile': 'none',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': '16384', 'worker_disk': '120', 'worker_vcpu': '4',
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None}
        ),
        (
            {'cluster_topology': 'ha', 'resource_profile': 'recommended','extra_workers_profile': 'day2inactive'},
            {'cluster_topology': 'ha', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2inactive',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': '16384', 'worker_disk': '120', 'worker_vcpu': '4',
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': False}
        ),
        (
            {'cluster_topology': 'ha', 'resource_profile': 'recommended','extra_workers_profile': 'day2active'},
            {'cluster_topology': 'ha', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2active',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': '16384', 'worker_disk': '120', 'worker_vcpu': '4',
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': True}
        ),
        (
            {'cluster_topology': 'compact', 'resource_profile': 'minimal','extra_workers_profile': 'none'},
            {'cluster_topology': 'compact', 'resource_profile': 'minimal', 'extra_workers_profile': 'none',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None}
        ),
        (
            {'cluster_topology': 'compact', 'resource_profile': 'minimal','extra_workers_profile': 'day2inactive'},
            {'cluster_topology': 'compact', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2inactive',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': False}
        ),
        (
            {'cluster_topology': 'compact', 'resource_profile': 'minimal','extra_workers_profile': 'day2active'},
            {'cluster_topology': 'compact', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2active',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': True}
        ),
        (
            {'cluster_topology': 'compact', 'resource_profile': 'recommended','extra_workers_profile': 'none'},
            {'cluster_topology': 'compact', 'resource_profile': 'recommended', 'extra_workers_profile': 'none',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None}
        ),
        (
            {'cluster_topology': 'compact', 'resource_profile': 'recommended','extra_workers_profile': 'day2inactive'},
            {'cluster_topology': 'compact', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2inactive',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': False}
        ),
        (
            {'cluster_topology': 'compact', 'resource_profile': 'recommended','extra_workers_profile': 'day2active'},
            {'cluster_topology': 'compact', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2active',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': True}
        ),
                (
            {'cluster_topology': 'sno', 'resource_profile': 'minimal','extra_workers_profile': 'none'},
            {'cluster_topology': 'sno', 'resource_profile': 'minimal', 'extra_workers_profile': 'none',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None}
        ),
        (
            {'cluster_topology': 'sno', 'resource_profile': 'minimal','extra_workers_profile': 'day2inactive'},
            {'cluster_topology': 'sno', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2inactive',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': False}
        ),
        (
            {'cluster_topology': 'sno', 'resource_profile': 'minimal','extra_workers_profile': 'day2active'},
            {'cluster_topology': 'sno', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2active',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': True}
        ),
        (
            {'cluster_topology': 'sno', 'resource_profile': 'recommended','extra_workers_profile': 'none'},
            {'cluster_topology': 'sno', 'resource_profile': 'recommended', 'extra_workers_profile': 'none',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '0',
             'master_memory': '32768','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None}
        ),
        (
            {'cluster_topology': 'sno', 'resource_profile': 'recommended','extra_workers_profile': 'day2inactive'},
            {'cluster_topology': 'sno', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2inactive',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '32768','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': False}
        ),
        (
            {'cluster_topology': 'sno', 'resource_profile': 'recommended','extra_workers_profile': 'day2active'},
            {'cluster_topology': 'sno', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2active',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '32768','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': True}
        )
    ]
)
def test_determine_cluster_topology(test_input, expected):
    result = preset.determine_cluster_topology(**test_input)
    TestCase().assertDictEqual(expected, result)

@pytest.mark.parametrize(
    "test_input,expected",
    [
        (
            {'ip_stack': 'v4'},
            {'ip_stack': 'v4', 'host_ip_stack': 'v4', 'provisioning_network_profile': 'Managed',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': '172.22.0.0/24', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': '',
            'external_network': '192.168.111.0/24',
            'provisioning_ip_subnet': None, 'mirror_images': None, 'base_static_ip': '80'}
        ),
        (
            {'ip_stack': 'v6'},
            {'ip_stack': 'v6', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Managed',
            'network_type': 'OVNKubernetes',
            'cluster_subnet_v4': '', 'cluster_host_prefix_v4': '', 'service_subnet_v4': '',
            'cluster_subnet_v6': 'fd01::/48', 'cluster_host_prefix_v6': '64', 'service_subnet_v6': 'fd02::/112',
            'cluster_network': 'fd01::/48', 'cluster_host_prefix': '64', 'service_network': 'fd02::/112',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': None, 'mirror_images': True, 'base_static_ip': '80'}
        ),
        (
            {'ip_stack': 'v4v6'},
            {'ip_stack': 'v4v6', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Managed',
            'network_type': 'OVNKubernetes',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': 'fd01::/48', 'cluster_host_prefix_v6': '64', 'service_subnet_v6': 'fd02::/112',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': None, 'mirror_images': None, 'base_static_ip': '80'}
        ),
        (
            {'ip_stack': 'v4', 'host_ip_stack': 'v6'},
            {'ip_stack': 'v4', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Managed',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': None, 'mirror_images': None, 'base_static_ip': '80'}
        ),
        (
            {'ip_stack': 'v4', 'host_ip_stack': 'v4v6'},
            {'ip_stack': 'v4', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Managed',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': None, 'mirror_images': None, 'base_static_ip': '80'}
        ),
        (
            {'ip_stack': 'v4', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Disabled'},
            {'ip_stack': 'v4', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Disabled',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': 'fd2e:6f44:5dd8:c956::/120', 'mirror_images': None, 'base_static_ip': '80'}
        ),
        (
            {'ip_stack': 'v4', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Disabled'},
            {'ip_stack': 'v4', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Disabled',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': '192.168.111.0/24', 'mirror_images': None, 'base_static_ip': '80'}
        ),
        (
            {'ip_stack': 'v6','provisioning_network_profile': 'Disabled',},
            {'ip_stack': 'v6', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Disabled',
            'network_type': 'OVNKubernetes',
            'cluster_subnet_v4': '', 'cluster_host_prefix_v4': '', 'service_subnet_v4': '',
            'cluster_subnet_v6': 'fd01::/48', 'cluster_host_prefix_v6': '64', 'service_subnet_v6': 'fd02::/112',
            'cluster_network': 'fd01::/48', 'cluster_host_prefix': '64', 'service_network': 'fd02::/112',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': 'fd2e:6f44:5dd8:c956::/120', 'mirror_images': True, 'base_static_ip': '80'}
        ),
        (
            {'ip_stack': 'v4v6', 'provisioning_network_profile': 'Disabled'},
            {'ip_stack': 'v4v6', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Disabled',
            'network_type': 'OVNKubernetes',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': 'fd01::/48', 'cluster_host_prefix_v6': '64', 'service_subnet_v6': 'fd02::/112',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': '192.168.111.0/24', 'mirror_images': None, 'base_static_ip': '80'}
        ),

    ]
)
def test_determine_network_topolog(test_input, expected):
    result = preset.determine_network_topology(**test_input)
    TestCase().assertDictEqual(expected, result)
