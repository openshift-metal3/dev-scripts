#!/bin/bash

# https://github.com/openshift-metalkube/dev-scripts/issues/141#issuecomment-474331659

oc --config ocp/auth/kubeconfig get csr -o name | xargs -n 1 oc --config ocp/auth/kubeconfig adm certificate approve
