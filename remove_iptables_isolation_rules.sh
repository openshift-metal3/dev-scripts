#!/bin/bash

set -xeu

source logging.sh

# libvirt sets up the networks so they're isolated, but in a
# multi-cluster environment we need them to be able to talk to
# each other. Drop the relevant rules that block traffic to the
# bare metal networks. This is done here, rather than in the host
# setup script, because it is less invasive for the most common
# single-cluster configuration.
#
# The command replaces the '-A' in the rule with '-D' and calling
# iptables for each. For example, this rule:
#
# -A FORWARD -o hive1bm -j REJECT --reject-with icmp-port-unreachable
#
# becomes this command
#
# iptables -D FORWARD -o hive1bm -j REJECT --reject-with icmp-port-unreachable
#
sudo iptables-save \
    | grep icmp-port-unreachable \
    | grep 'bm -' \
    | sed -e 's/-A/-D/' \
    | sudo xargs -L 1 iptables
