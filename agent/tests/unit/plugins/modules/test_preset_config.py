from __future__ import (absolute_import, division, print_function)
import unittest
__metaclass__ = type

import json
import pytest
from ansible.module_utils import basic
from unittest import TestCase
from unittest.mock import patch
from ansible.module_utils.common.text.converters import to_bytes
import ansible_collections.devscripts.agent.plugins.modules.preset_config as preset

# Set up Ansible module test mocks
def set_module_args(args):
    """prepare arguments so that they will be picked up during module creation"""
    args = json.dumps({'ANSIBLE_MODULE_ARGS': args})
    basic._ANSIBLE_ARGS = to_bytes(args)

class AnsibleExitJson(Exception):
    """Exception class to be raised by module.exit_json and caught by the test case"""
    pass

class AnsibleFailJson(Exception):
    """Exception class to be raised by module.fail_json and caught by the test case"""
    pass

def exit_json(*args, **kwargs):
    """function to patch over exit_json; package return data into an exception"""
    if 'changed' not in kwargs:
        kwargs['changed'] = False
    raise AnsibleExitJson(kwargs)

def fail_json(*args, **kwargs):
    """function to patch over fail_json; package return data into an exception"""
    kwargs['failed'] = True
    raise AnsibleFailJson(kwargs)

class TestPresetModuleArgs(unittest.TestCase):

    def setUp(self):
        self.mock_module_helper = patch.multiple(basic.AnsibleModule,
                                                 exit_json=exit_json,
                                                 fail_json=fail_json)
        self.mock_module_helper.start()
        self.addCleanup(self.mock_module_helper.stop)

    @pytest.mark.presets
    def test_module_fail_when_required_args_are_missing(self):
        with self.assertRaises(AnsibleFailJson):
            set_module_args({})
            preset.main()

    @pytest.mark.presets
    def test_module_fail_when_openshift_release_type_value_is_not_in_choices(self):
        with self.assertRaises(AnsibleFailJson):
            set_module_args({"ci_token": "test", "openshift_release_type": "fail"})
            preset.main()

    @pytest.mark.presets
    def test_module_fail_when_cluster_topology_value_is_not_in_choices(self):
        with self.assertRaises(AnsibleFailJson):
            set_module_args({"ci_token": "test", "cluster_topology": "fail"})
            preset.main()

    @pytest.mark.presets
    def test_module_fail_when_resource_profile_value_is_not_in_choices(self):
        with self.assertRaises(AnsibleFailJson):
            set_module_args({"ci_token": "test", "resource_profile": "fail"})
            preset.main()

    @pytest.mark.presets
    def test_module_fail_when_extra_workers_profile_value_is_not_in_choices(self):
        with self.assertRaises(AnsibleFailJson):
            set_module_args({"ci_token": "test", "extra_workers_profile": "fail"})
            preset.main()

    @pytest.mark.presets
    def test_module_fail_when_ip_stack_value_is_not_in_choices(self):
        with self.assertRaises(AnsibleFailJson):
            set_module_args({"ci_token": "test", "ip_stack": "fail"})
            preset.main()

    @pytest.mark.presets
    def test_module_fail_when_host_ip_stack_value_is_not_in_choices(self):
        with self.assertRaises(AnsibleFailJson):
            set_module_args({"ci_token": "test", "ip_stack": "fail"})
            preset.main()

    @pytest.mark.presets
    def test_module_fail_when_provisioning_network_profile_value_is_not_in_choices(self):
        with self.assertRaises(AnsibleFailJson):
            set_module_args({"ci_token": "test", "provisioning_network_profile": "fail"})
            preset.main()

@pytest.mark.parametrize(
    "test_input,expected",
    [
        pytest.param(
            # test_input
            {'cluster_topology': 'ha', 'resource_profile': 'minimal','extra_workers_profile': 'none'},
            # expected
            {'cluster_topology': 'ha', 'resource_profile': 'minimal', 'extra_workers_profile': 'none',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': '8192', 'worker_disk': '20', 'worker_vcpu': '2',
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None},
            marks=pytest.mark.cluster, id="ha resources=minimal extra_workers=none"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'ha', 'resource_profile': 'minimal','extra_workers_profile': 'day2inactive'},
            # expected
            {'cluster_topology': 'ha', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2inactive',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': '8192', 'worker_disk': '20', 'worker_vcpu': '2',
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': False},
            marks=pytest.mark.cluster, id="ha resources=minimal extra_workers=day2inactive"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'ha', 'resource_profile': 'minimal','extra_workers_profile': 'day2active'},
            # expected
            {'cluster_topology': 'ha', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2active',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': '8192', 'worker_disk': '20', 'worker_vcpu': '2',
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': True},
            marks=pytest.mark.cluster, id="ha resources=minimal extra_workers=day2active"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'ha', 'resource_profile': 'recommended','extra_workers_profile': 'none'},
            # expected
            {'cluster_topology': 'ha', 'resource_profile': 'recommended', 'extra_workers_profile': 'none',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': '16384', 'worker_disk': '120', 'worker_vcpu': '4',
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None},
            marks=pytest.mark.cluster, id="ha resources=recommended extra_workers=none"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'ha', 'resource_profile': 'recommended','extra_workers_profile': 'day2inactive'},
            # expected
            {'cluster_topology': 'ha', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2inactive',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': '16384', 'worker_disk': '120', 'worker_vcpu': '4',
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': False},
            marks=pytest.mark.cluster, id="ha resources=recommended extra_workers=day2inactive"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'ha', 'resource_profile': 'recommended','extra_workers_profile': 'day2active'},
            # expected
            {'cluster_topology': 'ha', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2active',
             'num_masters': '3', 'num_workers': '2', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': '16384', 'worker_disk': '120', 'worker_vcpu': '4',
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': True},
            marks=pytest.mark.cluster, id="ha resources=recommended extra_workers=day2active"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'compact', 'resource_profile': 'minimal','extra_workers_profile': 'none'},
            # expected
            {'cluster_topology': 'compact', 'resource_profile': 'minimal', 'extra_workers_profile': 'none',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None},
            marks=pytest.mark.cluster, id="compact resources=minimal extra_workers=none"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'compact', 'resource_profile': 'minimal','extra_workers_profile': 'day2inactive'},
            # expected
            {'cluster_topology': 'compact', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2inactive',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': False},
            marks=pytest.mark.cluster, id="compact resources=minimal extra_workers=day2inactive"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'compact', 'resource_profile': 'minimal','extra_workers_profile': 'day2active'},
            # expected
            {'cluster_topology': 'compact', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2active',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': True},
            marks=pytest.mark.cluster, id="compact resources=minimal extra_workers=day2active"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'compact', 'resource_profile': 'recommended','extra_workers_profile': 'none'},
            # expected
            {'cluster_topology': 'compact', 'resource_profile': 'recommended', 'extra_workers_profile': 'none',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None},
            marks=pytest.mark.cluster, id="compact resources=recommended extra_workers=none"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'compact', 'resource_profile': 'recommended','extra_workers_profile': 'day2inactive'},
            # expected
            {'cluster_topology': 'compact', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2inactive',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': False},
            marks=pytest.mark.cluster, id="compact resources=recommended extra_workers=day2inactive"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'compact', 'resource_profile': 'recommended','extra_workers_profile': 'day2active'},
            # expected
            {'cluster_topology': 'compact', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2active',
             'num_masters': '3', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': True},
            marks=pytest.mark.cluster, id="compact resources=recommended extra_workers=day2active"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'sno', 'resource_profile': 'minimal','extra_workers_profile': 'none'},
            # expected
            {'cluster_topology': 'sno', 'resource_profile': 'minimal', 'extra_workers_profile': 'none',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '0',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None},
            marks=pytest.mark.cluster, id="sno resources=minimal extra_workers=none"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'sno', 'resource_profile': 'minimal','extra_workers_profile': 'day2inactive'},
            # expected
            {'cluster_topology': 'sno', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2inactive',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': False},
            marks=pytest.mark.cluster, id="sno resources=minimal extra_workers=day2inactive"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'sno', 'resource_profile': 'minimal','extra_workers_profile': 'day2active'},
            # expected
            {'cluster_topology': 'sno', 'resource_profile': 'minimal', 'extra_workers_profile': 'day2active',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '16384','master_disk': '20', 'master_vcpu': '4',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '8192', 'extra_worker_disk': '20', 'extra_worker_vcpu': '2',
             'apply_extra_workers': True},
            marks=pytest.mark.cluster, id="sno resources=minimal extra_workers=day2active"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'sno', 'resource_profile': 'recommended','extra_workers_profile': 'none'},
            # expected
            {'cluster_topology': 'sno', 'resource_profile': 'recommended', 'extra_workers_profile': 'none',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '0',
             'master_memory': '32768','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': None, 'extra_worker_disk': None, 'extra_worker_vcpu': None,
             'apply_extra_workers': None},
            marks=pytest.mark.cluster, id="sno resources=recommended extra_workers=none"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'sno', 'resource_profile': 'recommended','extra_workers_profile': 'day2inactive'},
            # expected
            {'cluster_topology': 'sno', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2inactive',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '32768','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': False},
            marks=pytest.mark.cluster, id="sno resources=recommended extra_workers=day2inactive"
        ),
        pytest.param(
            # test_input
            {'cluster_topology': 'sno', 'resource_profile': 'recommended','extra_workers_profile': 'day2active'},
            # expected
            {'cluster_topology': 'sno', 'resource_profile': 'recommended', 'extra_workers_profile': 'day2active',
             'num_masters': '1', 'num_workers': '0', 'num_extra_workers': '1',
             'master_memory': '32768','master_disk': '120', 'master_vcpu': '8',
             'worker_memory': None, 'worker_disk': None, 'worker_vcpu': None,
             'extra_worker_memory': '16384', 'extra_worker_disk': '120', 'extra_worker_vcpu': '4',
             'apply_extra_workers': True},
            marks=pytest.mark.cluster, id="sno resources=recommended extra_workers=day2active"
        )
    ]
)
def test_determine_cluster_topology(test_input, expected):
    result = preset.determine_cluster_topology(**test_input)
    TestCase().assertDictEqual(expected, result)

@pytest.mark.parametrize(
    "test_input,expected",
    [
        pytest.param(
            # test_input
            {'ip_stack': 'v4'},
            # expected
            {'ip_stack': 'v4', 'host_ip_stack': 'v4', 'provisioning_network_profile': 'Managed',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': '172.22.0.0/24', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': '',
            'external_network': '192.168.111.0/24',
            'provisioning_ip_subnet': None, 'mirror_images': None, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v4"
        ),
        pytest.param(
            # test_input
            {'ip_stack': 'v6'},
            # expected
            {'ip_stack': 'v6', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Managed',
            'network_type': 'OVNKubernetes',
            'cluster_subnet_v4': '', 'cluster_host_prefix_v4': '', 'service_subnet_v4': '',
            'cluster_subnet_v6': 'fd01::/48', 'cluster_host_prefix_v6': '64', 'service_subnet_v6': 'fd02::/112',
            'cluster_network': 'fd01::/48', 'cluster_host_prefix': '64', 'service_network': 'fd02::/112',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': None, 'mirror_images': True, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v6"
        ),
        pytest.param(
            # test_input
            {'ip_stack': 'v4v6'},
            # expected
            {'ip_stack': 'v4v6', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Managed',
            'network_type': 'OVNKubernetes',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': 'fd01::/48', 'cluster_host_prefix_v6': '64', 'service_subnet_v6': 'fd02::/112',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': None, 'mirror_images': None, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v4v6"
        ),
        pytest.param(
            # test_input
            {'ip_stack': 'v4', 'host_ip_stack': 'v6'},
            # expected
            {'ip_stack': 'v4', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Managed',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': None, 'mirror_images': None, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v4 host_ip_stack=v6"
        ),
        pytest.param(
            # test_input
            {'ip_stack': 'v4', 'host_ip_stack': 'v4v6'},
            # expected
            {'ip_stack': 'v4', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Managed',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': None, 'mirror_images': None, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v4 host_ip_stack=v4v6"
        ),
        pytest.param(
            # test_input
            {'ip_stack': 'v4', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Disabled'},
            # expected
            {'ip_stack': 'v4', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Disabled',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': 'fd2e:6f44:5dd8:c956::/120', 'mirror_images': None, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v4 host_ip_stack=v6 nework_profile=disabled"
        ),
        pytest.param(
            # test_input
            {'ip_stack': 'v4', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Disabled'},
            # expected
            {'ip_stack': 'v4', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Disabled',
            'network_type': 'OpenShiftSDN',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': '', 'cluster_host_prefix_v6': '', 'service_subnet_v6': '',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': '192.168.111.0/24', 'mirror_images': None, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v4 host_ip_stack=v4v6 network_profile=disabled"
        ),
        pytest.param(
            # test_input
            {'ip_stack': 'v6','provisioning_network_profile': 'Disabled',},
            # expected
            {'ip_stack': 'v6', 'host_ip_stack': 'v6', 'provisioning_network_profile': 'Disabled',
            'network_type': 'OVNKubernetes',
            'cluster_subnet_v4': '', 'cluster_host_prefix_v4': '', 'service_subnet_v4': '',
            'cluster_subnet_v6': 'fd01::/48', 'cluster_host_prefix_v6': '64', 'service_subnet_v6': 'fd02::/112',
            'cluster_network': 'fd01::/48', 'cluster_host_prefix': '64', 'service_network': 'fd02::/112',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': 'fd2e:6f44:5dd8:c956::/120', 'mirror_images': True, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v6 network_profile=disabled"
        ),
        pytest.param(
            # test_input
            {'ip_stack': 'v4v6', 'provisioning_network_profile': 'Disabled'},
            # expected
            {'ip_stack': 'v4v6', 'host_ip_stack': 'v4v6', 'provisioning_network_profile': 'Disabled',
            'network_type': 'OVNKubernetes',
            'cluster_subnet_v4': '10.128.0.0/14', 'cluster_host_prefix_v4': '23', 'service_subnet_v4': '172.30.0.0/16',
            'cluster_subnet_v6': 'fd01::/48', 'cluster_host_prefix_v6': '64', 'service_subnet_v6': 'fd02::/112',
            'cluster_network': '10.128.0.0/14', 'cluster_host_prefix': '23', 'service_network': '172.30.0.0/16',
            'provisioning_network': 'fd00:1101::0/64', 'external_subnet_v4': '192.168.111.0/24', 'external_subnet_v6': 'fd2e:6f44:5dd8:c956::/120',
            'external_network': 'fd2e:6f44:5dd8:c956::/120',
            'provisioning_ip_subnet': '192.168.111.0/24', 'mirror_images': None, 'base_static_ip': '80'},
            marks=pytest.mark.network, id="ip_stack=v4v6 network_profile=disabled"
        ),

    ]
)
def test_determine_network_topology(test_input, expected):
    result = preset.determine_network_topology(**test_input)
    TestCase().assertDictEqual(expected, result)
