#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
generator="$script_dir/generate_external_worker_manifests.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/inventory.json" <<'EOF'
{
  "nodes": [
    {
      "name": "external-worker-0",
      "bootMACAddress": "52:54:00:11:22:33",
      "architecture": "aarch64",
      "labels": {"example.com/worker-class": "external"},
      "bmc": {
        "address": "redfish-virtualmedia+https://bmc.example.test/redfish/v1/Systems/1",
        "credentialsName": "external-worker-0-bmc",
        "disableCertificateVerification": true
      },
      "rootDeviceHints": {"deviceName": "/dev/nvme0n1"},
      "customDeploy": {"method": "install_coreos"},
      "userData": {
        "name": "worker-user-data-managed",
        "namespace": "openshift-machine-api"
      },
      "preprovisioningNetworkData": {
        "name": "external-worker-0-network-data",
        "dataKey": "networkData",
        "nmstate": {
          "interfaces": [
            {
              "name": "eno1",
              "type": "ethernet",
              "state": "up",
              "mac-address": "52:54:00:11:22:33",
              "ipv4": {"enabled": true, "dhcp": true},
              "ipv6": {"enabled": false}
            }
          ]
        }
      }
    }
  ]
}
EOF

"$generator" "$test_dir/inventory.json" "$test_dir/manifests.json" openshift-machine-api

jq -e '
    .kind == "List"
    and (.items | length == 3)
    and .items[0].kind == "Secret"
    and .items[0].metadata.name == "external-worker-0-network-data"
    and (.items[0].stringData.nmstate | fromjson | .interfaces[0].name) == "eno1"
    and (.items[0].stringData.networkData | fromjson | .interfaces[0].name) == "eno1"
    and .items[0].stringData.nmstate == .items[0].stringData.networkData
    and .items[1].kind == "ConfigMap"
    and .items[1].metadata.name == "external-worker-0"
    and .items[1].metadata.annotations["dev-scripts.openshift.io/purpose"] == "external-worker-claim-barrier"
    and .items[2].kind == "BareMetalHost"
    and .items[2].spec.online == false
    and .items[2].spec.consumerRef.kind == "ConfigMap"
    and .items[2].spec.consumerRef.name == "external-worker-0"
    and .items[2].spec.bmc.credentialsName == "external-worker-0-bmc"
    and .items[2].spec.bmc.disableCertificateVerification == true
    and .items[2].spec.preprovisioningNetworkDataName == "external-worker-0-network-data"
    and .items[2].spec.rootDeviceHints.deviceName == "/dev/nvme0n1"
    and .items[2].spec.customDeploy.method == "install_coreos"
    and ([.. | objects | keys[]] | index("password") | not)
' "$test_dir/manifests.json" >/dev/null

jq '.nodes[0].bmc.password = "must-not-be-accepted"' \
    "$test_dir/inventory.json" > "$test_dir/invalid.json"
if "$generator" "$test_dir/invalid.json" "$test_dir/invalid-manifests.json" openshift-machine-api; then
    echo "Inventory containing a BMC password was accepted" >&2
    exit 1
fi

jq '.nodes += [(.nodes[0]
    | .name = "external-worker-1"
    | .bootMACAddress = "52:54:00:11:22:34"
    | .preprovisioningNetworkData.name = "external-worker-1-network-data")]' \
    "$test_dir/inventory.json" > "$test_dir/two-workers.json"
"$generator" "$test_dir/two-workers.json" "$test_dir/two-worker-manifests.json" openshift-machine-api
jq -e '.items | length == 6' "$test_dir/two-worker-manifests.json" >/dev/null

jq '.nodes[1].preprovisioningNetworkData.name = .nodes[0].preprovisioningNetworkData.name' \
    "$test_dir/two-workers.json" > "$test_dir/duplicate-network-secret.json"
if "$generator" "$test_dir/duplicate-network-secret.json" "$test_dir/duplicate-network-secret-manifests.json" openshift-machine-api; then
    echo "Inventory with conflicting network-data Secret names was accepted" >&2
    exit 1
fi

jq '.nodes[1].bootMACAddress = (.nodes[0].bootMACAddress | ascii_upcase)' \
    "$test_dir/two-workers.json" > "$test_dir/duplicate-boot-mac.json"
if "$generator" "$test_dir/duplicate-boot-mac.json" "$test_dir/duplicate-boot-mac-manifests.json" openshift-machine-api; then
    echo "Inventory with duplicate boot MAC addresses was accepted" >&2
    exit 1
fi

echo "External worker manifest generator tests passed"
