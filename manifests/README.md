A number of manifests which will be deployed during installation.

Assumption is that the list of sorted manifests is applicable using:

```bash
for MANIFEST in $(ls -1 | sort -h);
do
  kubectl apply -f $MANIFEST
done
```

> **Important note:** We do not assume that all manifests can be applied in one
> go using `kubectl apply -f .` as some manifests will depend on others,
> i.e. a manifest introducing a CRD is needed before the CR can be created.
