# CNV Manifests

## KubeVirt

Done as described here:

https://kubevirt.io/user-guide/docs/latest/administration/intro.html#2-alternative-flow-aka-operator-flow

Created using:

```
VERSION=v0.15.0
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

TBD

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
