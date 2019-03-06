#!/bin/bash

set -o pipefail

function apply_ignition_patches() {
local kind
local target
local target_name
local wd
local current
local current_patch_name

kind="$1"
target="$2"
wd=$(mktemp -d)
target_name="$(basename "$target")"

current="$target"
for patch in $(ls "${PWD}/ignition_patches/${kind}/"*.json); do
    current_patch_name="$(basename "$patch")"
    (>2& echo "Patching "$current" with "$patch"")
    jsonpatch "$current" "$patch" > "${wd}/${target_name}_${current_patch_name}"
    current="${wd}/${target_name}_${current_patch_name}"
done

# Process also generated if they exist
for patch in $(ls "${PWD}/ignition_patches/generated/${kind}/"*.json); do
    current_patch_name="$(basename "$patch")"
    (>2& echo "Patching "$current" with "$patch"")
    jsonpatch "$current" "$patch" > "${wd}/${target_name}_${current_patch_name}"
    current="${wd}/${target_name}_${current_patch_name}"
done

if [[ "$current" != "$target" ]]; then
    sudo cp "$current" "$target"
fi
}

function patch_node_ignition() {
    local kind
    local bootstrap
    local wd
    local config

    kind="$1"
    bootstrap="$2"
    wd="$(mktemp -d)"

    # Wait for the release config to be pulled
    while
        config=$($SSH "core@$bootstrap" \
            sudo ls "/etc/mcs/bootstrap/machine-configs/${kind}*")
        [ -z "$config" ]
    do
        (>&2 echo "Waiting 5 seconds more for $kind Release MachineConfig to be pulled...")
        sleep 5
    done

    # Retrieve the MachineConfig
    $SSH "core@$bootstrap" \
        sudo cat "$config" > "${wd}/${kind}.yaml"

    apply_yaml_patches "$kind" "${wd}/${kind}.yaml"

    # Put it back
    # TODO: Put a check so we only do this step if the yaml was successfully generated
    $SSH < "${wd}/${kind}.yaml" "core@$bootstrap" sudo dd of="$config"
}

function machineconfig_generate_patches() {
    set -x
    local kind
    local path
    local value
    local search_path
    local config_type
    local files_template
    local units_template
    local octal_mode
    local decimal_mode
    local dest_path
    local ifs
    local simple_name
    local content

    files_template=$(cat <<'EOF'
[{"op": "add", "path": "/${path}/-", "value": {"filesystem": "root", "path": "${dest_path}", "user": {"name": "root"}, "contents": {"source": "data:,${value}", "verification": {}}, "mode": ${decimal_mode}}}]
EOF
)
    units_template=$(cat <<'EOF'
[{"op": "add", "path": "/${path}/-", "value": {"contents": "${value}", "enabled": true, "name": "${simple_name}"}}]
EOF
)

    kind="$1"
    search_path="machineconfig/${kind}"

    ifs="$IFS"
    IFS=$'\n'
    rm -fr "${PWD}/ignition_patches/generated/${kind}"
    for file in $(find "$search_path" -type f -printf "%P\n"); do
        path="$(dirname "$file")"
        config_type="$(basename "$path")"

        if [[ "$config_type" == "files" ]]; then
            simple_name="$(basename "$file" | cut -f1 -d' ')"
            dest_path="$(basename "$file" | cut -f2 -d' '| base64 -d)"
            value="$(jq -sRr @uri "${search_path}/${file}")"
            octal_mode=$(stat -c '%a' "${search_path}/${file}")
            decimal_mode=$(printf "%d" "0${octal_mode}")
            mkdir -p "${PWD}/ignition_patches/generated/${kind}"
            path="$path" dest_path="$dest_path" value="$value" decimal_mode="$decimal_mode" envsubst <<< "$files_template" | tee "ignition_patches/generated/${kind}/${simple_name}.json"
        elif [[ "$config_type" == "units" ]]; then
            simple_name="$(basename "$file")"
            if [[ "$simple_name" == *".envsubst" ]]; then
                # The file needs to have variables substituted from env
                content="$(envsubst < "${search_path}/${file}")"
                simple_name="${simple_name%".envsubst"}"
            else
                content="$(cat "${search_path}/${file}")"
            fi
            value="$(sed ':a;N;$!ba;s/\n/\\n/g' <<< "$content")"
            mkdir -p "${PWD}/ignition_patches/generated/${kind}"
            path="$path" value="$value" simple_name="$simple_name" envsubst <<< "$units_template" | tee "ignition_patches/generated/${kind}/${simple_name}.json"
        else
            (>&2 echo "unknown type")
        fi
    done
    IFS="$ifs"
    set +x
}

function apply_yaml_patches() {
    local kind
    local target
    local wd

    kind="$1"
    target="$2"
    wd=$(mktemp -d)

    # Convert to json so we can use jsonpatch
    yq '.' "$target" > "${wd}/${kind}.json"
    apply_ignition_patches "$kind" "${wd}/${kind}.json"

    # Back to yaml
    yq -y '.' < "${wd}/${kind}.json" | sudo tee "$target"
}

# Add if-name param to etcd discovery container on masters
function add_if_name_to_etcd_discovery() {
    local ip
    local if_name
    local wd
    local master_config

    ip="$1"
    if_name="$2"
    wd=$(mktemp -d)

    # Find master machine config name
    while [ -z $($SSH "core@$ip" sudo ls /etc/mcs/bootstrap/machine-configs/master*) ]; do sleep 5; done

    master_config=$($SSH "core@$ip" sudo ls /etc/mcs/bootstrap/machine-configs/master*)
    $SSH "core@$ip" sudo cat "${master_config}" > "${wd}/master.yaml"
    # Extract etcd-member.yaml part
    yq -r ".spec.config.storage.files[] | select(.path==\"/etc/kubernetes/manifests/etcd-member.yaml\") | .contents.source" "${wd}/master.yaml" | sed 's;data:,;;' > "${wd}/etcd-member.urlencode"
    # URL decode
    cat "${wd}/etcd-member.urlencode" | urldecode > "${wd}/etcd-member.yaml"
    # Add a new param to args in discovery container
    sed -i "s;- \"run\";- \"run\"\\n    - \"--if-name=${if_name}\";g" "${wd}/etcd-member.yaml"
    # URL encode yaml
    cat "${wd}/etcd-member.yaml" | jq -sRr @uri > "${wd}/etcd-member.urlencode_updated"
    # Replace etcd-member contents in the yaml
    sed -i "s;$(cat ${wd}/etcd-member.urlencode);$(cat ${wd}/etcd-member.urlencode_updated);g" "${wd}/master.yaml"
    # Copy the changed file back to bootstrap
    cat "${wd}/master.yaml" | $SSH "core@$ip" sudo dd of="${master_config}"
}

function net_iface_dhcp_ip() {
local netname
local hwaddr

netname="$1"
hwaddr="$2"
sudo virsh net-dhcp-leases "$netname" | grep -q "$hwaddr" || return 1
sudo virsh net-dhcp-leases "$netname" | awk -v hwaddr="$hwaddr" '$3 ~ hwaddr {split($5, res, "/"); print res[1]}'
}

function domain_net_ip() {
    local domain
    local bridge_name
    local net
    local hwaddr
    local rc

    domain="$1"
    net="$2"


    bridge_name=$(sudo virsh net-dumpxml "$net" | "${PWD}/pyxpath" "//bridge/@name" -)
    hwaddr=$(virsh dumpxml "$domain" | "${PWD}/pyxpath" "//devices/interface[source/@bridge='$bridge_name']/mac/@address" -)
    rc=$?
    if [ $rc -ne 0 ]; then
        return $rc
    fi

    net_iface_dhcp_ip "$net" "$hwaddr"
}

function wait_for_json() {
    local name
    local url
    local curl_opts
    local timeout

    local start_time
    local curr_time
    local time_diff

    name="$1"
    url="$2"
    timeout="$3"
    shift 3
    curl_opts="$@"
    echo -n "Waiting for $name to respond"
    start_time=$(date +%s)
    until curl -g -X GET "$url" "${curl_opts[@]}" 2> /dev/null | jq '.' 2> /dev/null > /dev/null; do
        echo -n "."
        curr_time=$(date +%s)
        time_diff=$(($curr_time - $start_time))
        if [[ $time_diff -gt $timeout ]]; then
            echo "\nTimed out waiting for $name"
            return 1
        fi
        sleep 5
    done
    echo " Success!"
    return 0
}

function network_ip() {
    local network
    local rc

    network="$1"
    ip="$(sudo virsh net-dumpxml "$network" | "${PWD}/pyxpath" "//ip/@address" -)"
    rc=$?
    if [ $rc -ne 0 ]; then
        return $rc
    fi
    echo "$ip"
}

function urldecode() {
  echo -e "$(sed 's/+/ /g;s/%\(..\)/\\x\1/g;')"
}
