#!/usr/bin/bash

set -eux

export GIT_SSL_NO_VERIFY=true
UHC_TOKEN="${UHC_TOKEN:-}"

figlet "Updating uhc information" | lolcat

if [ -z "$UHC_TOKEN" ]; then
    echo Missing UHC_TOKEN environment variable
    exit 1
fi

eval "$(go env)"

go get --insecure -u gitlab.cee.redhat.com/service/uhc-cli/cmd/uhc
export PATH=$GOPATH/bin:$PATH
uhc login --token=$UHC_TOKEN
CLUSTERID="'$(oc get clusterversion version -o jsonpath={.spec.clusterID})'"
ID=$(uhc get /api/clusters_mgmt/v1/clusters --parameter search="external_id = $CLUSTERID" | jq -r '.items[0].id')
URL=https://$(oc get route console -n kubevirt-web-ui -o jsonpath='{.spec.host}')
echo """{
  \"cloud_provider\": {
    \"id\": \"bare_metal\"
  },
  \"region\": {
    \"id\": \"boston\"
  },
  \"console\": {
    \"url\": \"$URL\"
  }
}""" > uhc.json
uhc patch /api/clusters_mgmt/v1/clusters/$ID --body uhc.json
