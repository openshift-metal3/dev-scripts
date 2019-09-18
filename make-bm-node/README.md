Registering Bare Metal Hosts
============================

The `make-bm-worker` tool may be a more convenient way of creating
YAML definitions for workers than editing the files directly.

```
$ go run make-bm-worker/main.go -address ipmi://192.168.111.1:6233 -password password -user admin worker-99
---
apiVersion: v1
kind: Secret
metadata:
  name: worker-99-bmc-secret
type: Opaque
data:
  username: YWRtaW4=
  password: cGFzc3dvcmQ=

---
apiVersion: metalkube.org/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-99
spec:
  online: true
  bmc:
    address: ipmi://192.168.111.1:6233
    credentialsName: worker-99-bmc-secret
```

The output can be passed directly to `oc apply` like this:

```
$ go run make-bm-worker/main.go -address ipmi://192.168.111.1:6233 -password password -user admin worker-99 | oc apply -f - -n openshift-machine-api 
```

Include the `-image` option to include the image settings needed to
trigger immediate provisioning:

```
$ go run make-bm-worker/main.go -address ipmi://192.168.111.1:6233 -password password -user admin -image worker-99
---
apiVersion: v1
kind: Secret
metadata:
  name: worker-99-bmc-secret
type: Opaque
data:
  username: YWRtaW4=
  password: cGFzc3dvcmQ=

---
apiVersion: metalkube.org/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-99
spec:
  online: true
  bmc:
    address: ipmi://192.168.111.1:6233
    credentialsName: worker-99-bmc-secret

  userData:
    namespace: openshift-machine-api
    name: worker-user-data
  image:
    url: "http://172.22.0.1/images/rhcos-ootpa-latest.qcow2"
    checksum: "http://172.22.0.1/images/rhcos-ootpa-latest.qcow2.md5sum"
```
