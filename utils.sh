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
    (>&2 echo "Patching "$current" with "$patch"")
    jsonpatch "$current" "$patch" > "${wd}/${target_name}_${current_patch_name}"
    current="${wd}/${target_name}_${current_patch_name}"
done

# Process also generated if they exist
for patch in $(ls "${PWD}/ignition_patches/generated/${kind}/"*.json); do
    current_patch_name="$(basename "$patch")"
    (>&2 echo "Patching "$current" with "$patch"")
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
    yq -y '.' < "${wd}/${kind}.json" | sudo tee "$target" | sed -e 's/.*auth.*/***PULL_SECRET***/g'
}

function create_ignition_configs() {
    local assets_dir

    assets_dir="$1"

    $GOPATH/src/github.com/openshift-metalkube/kni-installer/bin/kni-install --dir "${assets_dir}" --log-level=debug create ignition-configs
}

function create_cluster() {
    local assets_dir

    assets_dir="$1"

    $GOPATH/src/github.com/openshift-metalkube/kni-installer/bin/kni-install --dir "${assets_dir}" --log-level=debug create cluster
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

function master_node_val() {
    local n
    local val

    n="$1"
    val="$2"

    jq -r ".nodes[${n}].${val}" $MASTER_NODES_FILE
}

function master_node_to_tf() {
    local master_idx
    local image_source
    local image_checksum
    local root_gb
    local root_device

    master_idx="$1"
    image_source="$2"
    image_checksum="$3"
    root_gb="$4"
    root_device="$5"

    name=$(master_node_val ${master_idx} "name")
    mac=$(master_node_val ${master_idx} "ports[0].address")
    local_gb=$(master_node_val ${master_idx} "properties.local_gb")
    cpu_arch=$(master_node_val ${master_idx} "properties.cpu_arch")

    ipmi_port=$(master_node_val ${master_idx} "driver_info.ipmi_port // \"\"")
    if [ -n "$ipmi_port" ]; then
        ipmi_port="\"ipmi_port\"=      \"${ipmi_port}\""
    fi
    ipmi_username=$(master_node_val ${master_idx} "driver_info.ipmi_username")
    ipmi_password=$(master_node_val ${master_idx} "driver_info.ipmi_password")
    ipmi_address=$(master_node_val ${master_idx} "driver_info.ipmi_address")

    deploy_kernel=$(master_node_val ${master_idx} "driver_info.deploy_kernel")
    deploy_ramdisk=$(master_node_val ${master_idx} "driver_info.deploy_ramdisk")

    cat <<EOF

resource "ironic_node_v1" "openshift-master-${master_idx}" {
  name = "$name"

  target_provision_state = "active"
  user_data = "\${file("master.ign")}"

  ports = [
    {
      "address" = "${mac}"
      "pxe_enabled" = "true"
    }
  ]

  properties {
    "local_gb" = "${local_gb}"
    "cpu_arch" =  "${cpu_arch}"
  }

  instance_info = {
    "image_source" = "${image_source}"
    "image_checksum" = "${image_checksum}"
    "root_gb" = "${root_gb}"
    "root_device" = "${root_device}"
  }

  driver = "ipmi"
  driver_info {
    ${ipmi_port}
    "ipmi_username"=  "${ipmi_username}"
    "ipmi_password"=  "${ipmi_password}"
    "ipmi_address"=   "${ipmi_address}"
    "deploy_kernel"=  "${deploy_kernel}"
    "deploy_ramdisk"= "${deploy_ramdisk}"
  }
}
EOF
}
