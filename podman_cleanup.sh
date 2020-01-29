#!/usr/bin/env bash
set -x

sudo podman stop --all
sudo podman rm --all --force
sudo podman image rm --all --force
