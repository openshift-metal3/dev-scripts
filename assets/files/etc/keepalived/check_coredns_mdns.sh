#!/bin/sh

DOMAIN="$(clusterinfo CLUSTER_DOMAIN)"
exec host -t SRV "_etcd-server-ssl._tcp.$DOMAIN" localhost > /dev/null 2> /dev/null
