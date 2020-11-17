Ignition config examples
========================

These examples can be used via the `IGNITION_EXTRA` variable to perform
additional configuration [via openshift-install](https://github.com/openshift/installer/blob/master/docs/user/customization.md#os-customization-unvalidated).

If modifying the examples it can be helpful to pre-validate the config
as described in the [ignition docs](https://github.com/coreos/ignition#config-validation) e.g:

  podman run --pull=always --rm -i quay.io/coreos/ignition-validate:release - < bond_vlan_404.ign

Note that the version of ignition may vary depending on the OpenShift version
being tested, the examples are made to work with the current master builds only

## VLAN testing

The `bond_vlan_404.ign` example is expected to be used with a specific config
e.g:

  export BAREMETAL_NETWORK_VLAN=404
  export BAREMETAL_NETWORK_VLAN_WORKAROUND=y
  export IGNITION_EXTRA=$HOME/dev-scripts/ignition/bond_vlan_404.ign
  export CLUSTER_PRO_IF=bond0
