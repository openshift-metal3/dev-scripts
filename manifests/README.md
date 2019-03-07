A number of manifests which will be deployed during installation.

These manifests will be applied by the installer in order, based on the
prefix, but note that currently kni-installer uses prefixes of 99 for most
openshift manifests, so we're starting with a number >100.

> **Important note:** We do not assume that all manifests can be applied in one
> go using `kubectl apply -f .` as some manifests will depend on others,
> i.e. a manifest introducing a CRD is needed before the CR can be created.
