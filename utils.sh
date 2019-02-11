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
for patch in "${PWD}/ignition_patches/${kind}/"*.json; do
    current_patch_name="$(basename "$patch")"
    jsonpatch "$current" "$patch" > "${wd}/${target_name}_${current_patch_name}"
    current="${wd}/${target_name}_${current_patch_name}"
done
sudo cp "$current" "$target"
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
