Assisted Deployment
==

The Assisted Deployment refers to the use of [assisted
service](https://github.com/openshift/assisted-service/) for deploying OpenShift nodes. Please, read
the Assisted Service documentation for more information about its architecture and how it works.

Pre-requisites
==

2 disks need to be created and added to the worker nodes. The disks should be
of, at least, 10GB each. Set the following variables in your `config.sh`
before configuring the development environment:

```bash
export VM_EXTRADISKS=true
export VM_EXTRADISKS_LIST="vda vdb"
export VM_EXTRADISKS_SIZE="10G"
```

Assisted in dev script
==

The assisted service deployment in a dev-script environment is done by running the
`assisted_deployment` target from the Makefile. This target will deploy three things:

- Local Storage operator
- Hive
- Assisted Service Operator


The first 2 are dependencies for the latter and they must be up and running before Assisted Service
can be deployed. The deployment steps take care of this already.

The deployment of those three services is done using their respective operators. The local storage
and hive operator deployments are not configurable, while the assisted service is. Please, refer to
the [config_example.sh](https://github.com/openshift-metal3/dev-scripts/blob/master/config_example.sh)
file for more info on what variables are exposed.


Clean up
==

Clean up is done using the `assisted_deploymnent_cleanup` target. This step will delete *only* the
assisted service related resources (including the namespace) and the hive resources. Local storage
operator will be kept as well as the rest of the `dev-script` deployed resources.
