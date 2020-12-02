#!/bin/bash

set -ex

if [[ $REMOVE_OLD_REPOS == "yes" ]]; then
    rm -f /etc/yum.repos.d/*
fi
