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
