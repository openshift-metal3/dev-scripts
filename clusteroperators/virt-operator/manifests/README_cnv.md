# CNV Manifests

## KubeVirt

Done as described here:

https://kubevirt.io/user-guide/docs/latest/administration/intro.html#2-alternative-flow-aka-operator-flow

Created using:

```
VERSION=v0.16.0
curl -Lo 10_cnv_kubevirt_op.yaml https://github.com/kubevirt/kubevirt/releases/download/$VERSION/kubevirt-operator.yaml
curl -Lo 11_cnv_kubevirt_cr.yaml https://github.com/kubevirt/kubevirt/releases/download/$VERSION/kubevirt-cr.yaml
cat > 12_cnv_kubevirt_config.yaml <<EOY
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubevirt-config
  namespace: kubevirt
data:
  debug.useEmulation: "true"
EOY
```

After creation you can wait for the application readiness with:

```
 kubectl wait kv kubevirt --for condition=Ready
```


### Running a VM

Apply this config https://github.com/kubevirt/demo/blob/master/manifests/vm.yaml


## CDI

CDI provides the DataVolume CRD to use with VMs.  Enable 'DataVolumes' feature
gate in the kubevirt configmap to use them.

```bash
VERSION=v1.6.0
curl -Lo 8_cnv_cdi_operator.yaml https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
curl -Lo 9_cnv_cdi_cr.yaml https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator-cr.yaml
cat > 12_cnv_kubevirt_config.yaml <<EOY
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubevirt-config
  namespace: kubevirt
data:
  debug.useEmulation: "true"
  feature-gates: "DataVolumes"
EOY
```

Manifests are from https://github.com/kubevirt/containerized-data-importer/releases.

## Network

Manifests are based on https://github.com/kubevirt/kubevirt-ansible/tree/master/roles/network-multus/templates

The list is as follows:

```
120_cni_plugins.yaml
121_sriovdp.yaml
122_sriov_crd.yaml
123_sriov_cni.yaml
124_ovs_cni.yaml
```
