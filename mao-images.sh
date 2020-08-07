#!/bin/bash

oc get configmap -n openshift-machine-api machine-api-operator-images -o jsonpath="{.data.images\.json}"
