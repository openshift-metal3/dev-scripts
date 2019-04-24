A number of workloads that we deploy to replicate summit demo workflow

## Description

- authentication using a dedicated super user
- dotner project with a mssqlserver pod
- kafka. requires ceph to be deployed previously
- nfs to be used for the windows vm. By default, requires access to internal network
- a windows vm connected through the brext bridges of the nodes. Required dev script to have been installed with https://github.com/openshift-metalkube/dev-scripts/pull/282.patch
- knative
- tweeting service using knative
- uhc modifications

## Variables

All those variables have default values, except for the last four ones, related to tweet service

- ADMIN_USER
- ADMIN_PASSWORD
- MSSQL_PASSWORD
- KAFKA_NAMESPACE
- KAFKA_CLUSTERNAME
- KAFKA_PVC_SIZE
- KAFKA_PRODUCER_TIMER
- KAFKA_PRODUCER_TOPIC
- WINDOWS_IMAGE
- VM_SIZE
- VM_MEMORY
- UHC_TOKEN
- CONSUMER_KEY
- CONSUMER_SECRET
- ACCESS_TOKEN
- ACCESS_TOKEN_SECRET
