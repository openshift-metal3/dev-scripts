# MetalLB test env

This scripts installs MetalLB into OCP, for test environment.

## Prerequisites

- Succeed to deploy OCP by dev-script
- IPv4 is enabled (Currently we targets IPv4. v4v6 case, we only support IPv4 for now)

## Quickstart

Make sure that OCP is deployed by dev-script

To configure MetalLB

```
$ cd <dev-script>/metallb
$ make config_metallb
```

### Check MetalLB pod status

```
$ export KUBECONIFG=<dev-script>/ocp/<cluster name>/auth/kubeconfig
$ oc get pod -n metallb-system
```

### Run E2E tests against development cluster

The test suite will run the appropriate tests against the cluster.

To run the E2E tests

```
$ cd <dev-script>/metallb
$ make run_e2e
```
