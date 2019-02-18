#!/bin/bash

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
    ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

    # Wait for the release config to be pulled
    while
        config=$(ssh "${ssh_opts[@]}" "core@$bootstrap" \
            sudo ls "/etc/mcs/bootstrap/machine-configs/${kind}*")
        [ -z "$config" ]
    do
        (>&2 echo "Waiting 5 seconds more for $kind Release MachineConfig to be pulled...")
        sleep 5
    done

    # Retrieve the MachineConfig
    ssh "${ssh_opts[@]}" "core@$bootstrap" \
        sudo cat "$config" > "${wd}/${kind}.yaml"

    apply_yaml_patches "$kind" "${wd}/${kind}.yaml"

    # Put it back
    ssh < "${wd}/${kind}.yaml" "${ssh_opts[@]}" "core@$bootstrap" sudo dd of="$config"
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
    hwaddr=$(sudo virsh dumpxml "$domain" | "${PWD}/pyxpath" "//devices/interface[source/@bridge='$bridge_name']/mac/@address" -)
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
