#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 INPUT_FILE OUTPUT_FILE NAMESPACE" >&2
    exit 2
fi

input_file=$1
output_file=$2
namespace=$3

if [[ ! -r "$input_file" ]]; then
    echo "External worker inventory is not readable: $input_file" >&2
    exit 1
fi

if ! jq -e '
    (.nodes | type == "array" and length > 0)
    and (([.nodes[].name] | length) == ([.nodes[].name] | unique | length))
    and all(.nodes[];
        (.name | type == "string" and length <= 63
            and test("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"))
        and (.bootMACAddress | type == "string" and test("(?i)^([0-9a-f]{2}:){5}[0-9a-f]{2}$"))
        and (.architecture | type == "string" and length > 0)
        and (.bmc | type == "object")
        and (.bmc.address | type == "string" and length > 0)
        and (.bmc.credentialsName | type == "string" and length <= 253
            and test("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$"))
        and ((.bmc | has("username") or has("password")) | not)
        and ((.bmc.disableCertificateVerification // false) | type == "boolean")
        and ((.labels // {}) | type == "object")
        and ((.rootDeviceHints // {}) | type == "object")
        and ((.customDeploy // {}) | type == "object")
        and ((.userData // {}) | type == "object")
        and ((.automatedCleaningMode // "metadata")
            | . == "metadata" or . == "disabled")
        and (if has("preprovisioningNetworkData") then
            (.preprovisioningNetworkData | type == "object")
            and (.preprovisioningNetworkData.nmstate | type == "object")
            and ((.preprovisioningNetworkData.name // (.name + "-preprov-network"))
                | type == "string" and length <= 253
                and test("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$"))
            and ((.preprovisioningNetworkData.dataKey // "nmstate")
                | . == "nmstate" or . == "networkData")
        else true end)
        and (has("online") | not)
    )
' "$input_file" >/dev/null; then
    echo "External worker inventory failed validation: $input_file" >&2
    exit 1
fi

mkdir -p "$(dirname "$output_file")"
temporary_output=$(mktemp "${output_file}.XXXXXX")
trap 'rm -f "$temporary_output"' EXIT

jq --arg namespace "$namespace" '
    def network_data_secret:
        . as $node
        | {
            apiVersion: "v1",
            kind: "Secret",
            metadata: {
                name: ($node.preprovisioningNetworkData.name // ($node.name + "-preprov-network")),
                namespace: $namespace
            },
            type: "Opaque",
            stringData: {
                (($node.preprovisioningNetworkData.dataKey // "nmstate")):
                    ($node.preprovisioningNetworkData.nmstate | tojson)
            }
        };

    def claim_barrier:
        . as $node
        | {
            apiVersion: "v1",
            kind: "ConfigMap",
            metadata: {
                name: $node.name,
                namespace: $namespace,
                annotations: {
                    "dev-scripts.openshift.io/purpose": "external-worker-claim-barrier"
                }
            },
            data: {
                notice: "Remove the BareMetalHost consumerRef only when provisioning is explicitly authorized."
            }
        };

    def bare_metal_host:
        . as $node
        | {
            apiVersion: "metal3.io/v1alpha1",
            kind: "BareMetalHost",
            metadata: {
                name: $node.name,
                namespace: $namespace,
                labels: ($node.labels // {})
            },
            spec: {
                online: false,
                bootMACAddress: $node.bootMACAddress,
                architecture: $node.architecture,
                automatedCleaningMode: ($node.automatedCleaningMode // "metadata"),
                consumerRef: {
                    apiVersion: "v1",
                    kind: "ConfigMap",
                    name: $node.name,
                    namespace: $namespace
                },
                bmc: {
                    address: $node.bmc.address,
                    credentialsName: $node.bmc.credentialsName,
                    disableCertificateVerification: (
                        if ($node.bmc | has("disableCertificateVerification"))
                        then $node.bmc.disableCertificateVerification
                        else false
                        end
                    )
                }
            }
        }
        | if ($node.rootDeviceHints // {} | length) > 0
          then .spec.rootDeviceHints = $node.rootDeviceHints else . end
        | if ($node.customDeploy // {} | length) > 0
          then .spec.customDeploy = $node.customDeploy else . end
        | if ($node.userData // {} | length) > 0
          then .spec.userData = $node.userData else . end
        | if $node.preprovisioningNetworkData
          then .spec.preprovisioningNetworkDataName = (
              $node.preprovisioningNetworkData.name // ($node.name + "-preprov-network")
          ) else . end;

    {
        apiVersion: "v1",
        kind: "List",
        items: [
            .nodes[]
            | (if .preprovisioningNetworkData then network_data_secret else empty end),
              claim_barrier,
              bare_metal_host
        ]
    }
' "$input_file" > "$temporary_output"

mv "$temporary_output" "$output_file"
trap - EXIT
echo "Generated external worker manifests: $output_file"
