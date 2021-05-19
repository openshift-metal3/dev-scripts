# MetalLB test env

This scripts installs MetalLB into OCP and setup FRR, for BGP test environment (i.e. MetalLB BGP mode)

## Note

This script must be temporal solution for that. In the future, metallb will be deployed through operator and
then this script should be deprecated.

## Prerequisites

- Succeed to deploy OCP by dev-script
- IPv4 is enabled (Currently we targets IPv4. v4v6 case, we only support IPv4 for now)

## Quickstart

Make sure that OCP is deployed by dev-script

To configure MetalLB BGP mode

```
$ cd <dev-script>/metallb
$ make config_bgp
```

To configure MetalLB Layer2 mode

```
$ cd <dev-script>/metallb
$ make config_l2
```

### Check MetalLB pod status

```
$ export KUBECONIFG=<dev-script>/ocp/<cluster name>/auth/kubeconfig
$ oc get pod -n metallb-system
```

### Login to FRR/BGP and check peering status (for MetalLB BGP mode)

`vtysh` is user interface for FRR.

```

$ sudo podman exec -it frr vtysh
Hello, this is FRRouting (version 7.5.1_git).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

bgp-sample-1# show bgp summary

IPv4 Unicast Summary:
BGP router identifier 192.168.122.1, local AS number 64512 vrf-id 0
BGP table version 0
RIB entries 0, using 0 bytes of memory
Peers 5, using 72 KiB of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt
192.168.111.20  4      64512         2         2        0    0    0 00:00:12            0        0
192.168.111.21  4      64512         2         2        0    0    0 00:00:12            0        0
192.168.111.22  4      64512         2         2        0    0    0 00:00:12            0        0
192.168.111.23  4      64512         2         2        0    0    0 00:00:11            0        0
192.168.111.24  4      64512         2         2        0    0    0 00:00:12            0        0

Total number of neighbors 5
```


### Create sample service

You can create sample service/pods in `testsvc.yaml`.

MetalLB BGP mode:

```
$ export KUBECONIFG=<dev-script>/ocp/<cluster name>/auth/kubeconfig
$ oc create -f <dev-script>/metallb/testsvc.yaml
$ oc get svc
NAME         TYPE           CLUSTER-IP      EXTERNAL-IP                            PORT(S)        AGE
kubernetes   ClusterIP      172.30.0.1      <none>                                 443/TCP        68m
nginx        LoadBalancer   172.30.114.97   192.168.10.0                           80:31384/TCP   27s
openshift    ExternalName   <none>          kubernetes.default.svc.cluster.local   <none>         48m
$ curl 192.168.10.0
<!DOCTYPE html>
<html>
(snip)
</html>
$ ip route
default via 147.75.92.142 dev bond0 proto static metric 300
10.0.0.0/8 via 10.64.74.130 dev bond0 proto static metric 300
10.64.74.130/31 dev bond0 proto kernel scope link src 10.64.74.131 metric 300
10.88.0.0/16 dev cni-podman0 proto kernel scope link src 10.88.0.1
147.75.92.142/31 dev bond0 proto kernel scope link src 147.75.92.143 metric 300
172.22.0.0/24 dev ostestpr proto kernel scope link src 172.22.0.1
192.168.10.0 proto bgp metric 20
	nexthop via 192.168.111.20 dev ostestbm weight 1
	nexthop via 192.168.111.21 dev ostestbm weight 1
	nexthop via 192.168.111.22 dev ostestbm weight 1
	nexthop via 192.168.111.23 dev ostestbm weight 1
	nexthop via 192.168.111.24 dev ostestbm weight 1
192.168.111.0/24 dev ostestbm proto kernel scope link src 192.168.111.1
192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1 linkdown
```

MetaLB Layer2 Mode:

```
$ export KUBECONIFG=<dev-script>/ocp/<cluster name>/auth/kubeconfig
$ oc create -f <dev-script>/metallb/testsvc.yaml
$ oc get svc
NAME         TYPE           CLUSTER-IP       EXTERNAL-IP                            PORT(S)        AGE
kubernetes   ClusterIP      172.30.0.1       <none>                                 443/TCP        3h19m
nginx        LoadBalancer   172.30.140.235   192.168.10.0                           80:30866/TCP   7m28s
openshift    ExternalName   <none>           kubernetes.default.svc.cluster.local   <none>         3h5m
$ curl 192.168.10.0
<!DOCTYPE html>
<html>
(snip)
</html>
```
