#!/bin/bash

source utils.sh

set -x
set -e

host="$1"

if [ -z "$host" ]; then
    echo "Usage: $0 HOST"
    exit 1
fi

oc --config ocp/auth/kubeconfig proxy &
proxy_pid=$!
function kill_proxy {
    kill $proxy_pid
}
trap kill_proxy EXIT SIGINT

HOST_PROXY_API_PATH="http://localhost:8001/apis/metal3.io/v1alpha1/namespaces/openshift-machine-api/baremetalhosts"

wait_for_json oc_proxy "${HOST_PROXY_API_PATH}" 10 -H "Accept: application/json" -H "Content-Type: application/json"

host_patch='
{
  "status": {
    "hardware": {
      "hostname": "'$host'",
      "nics": [],
      "systemVendor": {
        "manufacturer": "Red Hat",
        "productName": "product name",
        "serialNumber": ""
      },
      "firmware": {
        "bios": {
          "date": "04/01/2014",
          "vendor": "SeaBIOS",
          "version": "1.11.0-2.el7"
        }
      },
      "ramMebibytes": 0,
      "storage": [],
      "cpu": {
        "arch": "x86_64",
        "model": "Intel(R) Xeon(R) CPU E5-2630 v4 @ 2.20GHz",
        "clockMegahertz": 2199.998,
        "count": 4,
        "flags": []
      }
    }
  }
}
'

echo "PATCHING HOST"
echo "${host_patch}" | jq .

curl -s \
     -X PATCH \
     ${HOST_PROXY_API_PATH}/${host}/status \
     -H "Content-type: application/merge-patch+json" \
     -d "${host_patch}"

oc get baremetalhost -n openshift-machine-api -o yaml "${host}"
