#!/usr/bin/env bash

function etcd_members {
    declare -r domain="$1"
    dig +noall +answer -t SRV "_etcd-server-ssl._tcp.$domain" | awk '{print $NF}'
}

function first_a_addr {
    declare -r name="$1"
    dig +noall +answer "$name"  | awk '$4 == "A" {print $NF; exit}'
}

function get_backends {
    declare -r domain="$1"
    declare -r api_port="$2"
    local ip

    for item in $(etcd_members "$domain"); do
        if ip="$(first_a_addr "$item")" && [[ -n "$ip" ]]; then
            echo "   server $item ${ip}:$api_port weight 1 verify none check check-ssl inter 3s fall 3 rise 3"
        fi
    done
}

function has_master_api_lb_topology_changed {
    declare -r domain="$1"
    declare -r cfg_path="$2"
    local ip
    local haproxy_cfg_ip

    for item in $(etcd_members "$domain"); do
        ip=$(first_a_addr "$item")
        haproxy_cfg_ip=$(awk -v "server=$item" '$2 == server {print substr($3, 0, index($3, ":") - 1); exit}' "$cfg_path")
        if [[ -n "$ip" ]]; then
           if [[ "$haproxy_cfg_ip" != "$ip" ]]; then
               return 0
           fi
        fi
    done
    return 1
}

function generate_cfg {
    declare -r template_path="$1"
    declare -r cfg_path="$2"
    declare -r domain="$3"
    declare -r api_port="$4"
    declare -r STAT_PORT="$5"
    local BACKENDS

    BACKENDS="$(get_backends "$domain" "$api_port")"

    export BACKENDS
    export STAT_PORT
    /usr/libexec/platform-python -c "from __future__ import print_function
import os
with open('${template_path}', 'r') as f:
    content = f.read()
with open('${cfg_path}', 'w') as dest:
    print(os.path.expandvars(content), file=dest)"
}

function ensure_prerouting_rules {
    declare -r api_vip="$1"
    declare -r api_port="$2"
    declare -r lb_port="$3"
    declare -r rules=$(iptables -w 10 -L PREROUTING -n -t nat --line-numbers | awk '/OCP_API_LB_REDIRECT/ {print $1}'  | tac)
    if [[ -z "$rules" ]]; then
            (>&2 echo "Setting prerouting rule from ${api_vip}:${api_port} to port $lb_port")
            iptables -t nat -I PREROUTING --src 0/0 --dst "$api_vip" -p tcp --dport "$api_port" -j REDIRECT --to-ports "$lb_port" -m comment --comment "OCP_API_LB_REDIRECT"
    fi
}

function clean_prerouting_rules {
    (>&2 echo "Deleting API HAProxy IPtables rule")

    declare -r rules=$(iptables -w 10 -L PREROUTING -n -t nat --line-numbers | awk '/OCP_API_LB_REDIRECT/ {print $1}'  | tac)
    for rule in $rules; do
       iptables -t nat -D PREROUTING  "$rule"
    done

    trap - SIGINT SIGTERM
}
