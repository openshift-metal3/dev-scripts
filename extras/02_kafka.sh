#!/usr/bin/bash

function check_ceph_pool {
    # Function to check the existence of Ceph pool
    NS=openshift-storage
    LABEL='app=rook-ceph-tools'
    PODNAME=`oc get pod -n ${NS} -l ${LABEL} --no-headers -o name`
    CRD_POOL_NAME=`oc get cephblockpool.ceph.rook.io -n ${NS} --no-headers -o name | cut -d/ -f 2`
    GET_CEPH_POOL="ceph osd pool get ${CRD_POOL_NAME} size"
    SIZE=`oc rsh -n ${NS} ${PODNAME} ${GET_CEPH_POOL}`
    if [[ ${PIPESTATUS} == 0 ]]
    then
        echo "Ceph Pool Exists: ${CRD_POOL_NAME}"
    else
        echo "Ceph Pool does not exist"
        exit -1
    fi
}

set -eux
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/../"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${BASEDIR}/common.sh
check_ceph_pool

# Kafka Strimzi configs
KAFKA_NAMESPACE=${KAFKA_NAMESPACE:-strimzi}
KAFKA_CLUSTERNAME=${KAFKA_CLUSTERNAME:-strimzi}
KAFKA_PVC_SIZE=${KAFKA_PVC_SIZE:-100}
KAFKA_RETENTION_PERIOD_HOURS=${KAFKA_RETENTION_PERIOD_HOURS:-24}
# Kafka producer will generate 10 msg/sec/pod with a value of 100 (by default)
KAFKA_PRODUCER_TIMER=${KAFKA_PRODUCER_TIMER:-"100"}
KAFKA_PRODUCER_TOPIC=${KAFKA_PRODUCER_TOPIC:-strimzi-topic}
# Prometheus
PROMETHEUS_SCRAPE_PACE=${PROMETHEUS_SCRAPE_PACE:-"10s"}

figlet "Deploying Kafka Strimzi" | lolcat
eval "$(go env)"

STRIMZI_VERSION="0.11.2"
KAFKA_PRODUCER_VERSION="7463f3d9790229d70304805e327e58406e950f1e"
export KAFKAPATH="$GOPATH/src/github.com/strimzi/strimzi-kafka-operator"
export KAFKAPRODUCER_PATH="$GOPATH/src/github.com/scholzj/kafka-test-apps"
cd $KAFKAPATH

# Pinning Strimzi to the latest stable release
git reset --hard tags/${STRIMZI_VERSION}

# Apply RBAC
oc new-project ${KAFKA_NAMESPACE}
sed -i "s/namespace: .*/namespace: ${KAFKA_NAMESPACE}/" install/cluster-operator/*RoleBinding*.yaml
oc apply -f install/cluster-operator/020-RoleBinding-strimzi-cluster-operator.yaml -n ${KAFKA_NAMESPACE}
oc apply -f install/cluster-operator/031-RoleBinding-strimzi-cluster-operator-entity-operator-delegation.yaml -n ${KAFKA_NAMESPACE}
oc apply -f install/cluster-operator/032-RoleBinding-strimzi-cluster-operator-topic-operator-delegation.yaml -n ${KAFKA_NAMESPACE}

# Install Operator
oc apply -f install/cluster-operator -n ${KAFKA_NAMESPACE}
sleep 5
oc wait --for condition=ready pod -l name=strimzi-cluster-operator -n ${KAFKA_NAMESPACE} --timeout=300s

# Modify Kafka cluster & Deploy
sed -i "s/my-cluster/${KAFKA_CLUSTERNAME}/" metrics/examples/kafka/kafka-metrics.yaml
sed -i "s/1Gi/${KAFKA_PVC_SIZE}Gi/" metrics/examples/kafka/kafka-metrics.yaml
sed -i "/log.message.format.version: \"2.1\"/a\      log.retention.hours: ${KAFKA_RETENTION_PERIOD_HOURS}" metrics/examples/kafka/kafka-metrics.yaml
sed -i "s/my-cluster/${KAFKA_CLUSTERNAME}/" metrics/examples/kafka/kafka-connect-metrics.yaml
sed -i "s/my-connect/${KAFKA_CLUSTERNAME}/" metrics/examples/kafka/kafka-connect-metrics.yaml
oc apply -f metrics/examples/kafka/kafka-metrics.yaml -n ${KAFKA_NAMESPACE}
sleep 5
oc wait --for condition=ready pod -l strimzi.io/cluster=${KAFKA_CLUSTERNAME} -n ${KAFKA_NAMESPACE} --timeout=300s
oc apply -f metrics/examples/kafka/kafka-connect-metrics.yaml -n ${KAFKA_NAMESPACE}
sleep 5
oc wait --for condition=ready pod -l strimzi.io/kind=KafkaConnect -n ${KAFKA_NAMESPACE} --timeout=600s

# Modify Prometheus & Deploy
sed -i "s/namespace: .*/namespace: ${KAFKA_NAMESPACE}/" metrics/examples/prometheus/prometheus.yaml
sed -i "s/myproject/${KAFKA_CLUSTERNAME}/" metrics/examples/prometheus/prometheus.yaml
sed -i "s/10s/${PROMETHEUS_SCRAPE_PACE}/g" metrics/examples/prometheus/prometheus.yaml
oc apply -f metrics/examples/prometheus/prometheus.yaml -n ${KAFKA_NAMESPACE}
oc apply -f metrics/examples/prometheus/alerting-rules.yaml -n ${KAFKA_NAMESPACE}
sleep 5
oc wait --for condition=ready pod -l name=prometheus -n ${KAFKA_NAMESPACE} --timeout=300s
oc apply -f metrics/examples/prometheus/alertmanager.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l name=alertmanager -n ${KAFKA_NAMESPACE} --timeout=300s

# Deploy Grafana
oc apply -f metrics/examples/grafana/grafana.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l name=grafana -n ${KAFKA_NAMESPACE} --timeout=300s

# Expose Grafana & Prometheus
oc expose svc prometheus -n ${KAFKA_NAMESPACE} || echo "Prometheus route already exists" 
oc expose svc grafana -n ${KAFKA_NAMESPACE} || echo "Grafana route already exists" 

figlet "Deploying Kafka Producer/Consumer" | lolcat

# Kafka Producer/Consumer Deployment
cd $KAFKAPRODUCER_PATH 

# Pinning Strimzi to the latest stable release
git checkout ${KAFKA_PRODUCER_VERSION}

# Modify & Deploy Kafka Producer/Consumer
sed -i "s/my-cluster-kafka-bootstrap:9092/${KAFKA_CLUSTERNAME}-kafka-bootstrap:9092/" kafka-producer.yaml
sed -i "s/my-cluster-kafka-bootstrap:9092/${KAFKA_CLUSTERNAME}-kafka-bootstrap:9092/" kafka-consumer.yaml
sed -i "s/my-topic/${KAFKA_PRODUCER_TOPIC}/" kafka-producer.yaml
sed -i "s/my-topic/${KAFKA_PRODUCER_TOPIC}/" kafka-consumer.yaml
sed -i "s/\"10000\"/\"${KAFKA_PRODUCER_TIMER}\"/" kafka-producer.yaml
oc apply -f kafka-producer.yaml -n ${KAFKA_NAMESPACE}
oc apply -f kafka-consumer.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l app=kafka-consumer -n ${KAFKA_NAMESPACE} --timeout=300s

# Add Grafana Dashboards and Datasource
GRAFANA_ROUTE=`oc get route grafana -n ${KAFKA_NAMESPACE} --template='{{ .spec.host }}'`
PROMETHEUS_ROUTE=`oc get route prometheus -n ${KAFKA_NAMESPACE} --template='{{ .spec.host }}'`
curl -X "POST" "http://${GRAFANA_ROUTE}/api/datasources" -H "Content-Type: application/json" --user admin:admin --data-binary '{ "name":"Prometheus","type":"prometheus","access":"proxy","url":"http://'${PROMETHEUS_ROUTE}'","basicAuth":false,"isDefault":true }'

# build and POST the Kafka dashboard to Grafana
$DIR/kafka-dashboards/dashboard-template.sh $DIR/kafka-dashboards/strimzi-kafka.json > $DIR/kafka-dashboards/strimzi-kafka-dashboard.json

sed -i 's/${DS_PROMETHEUS}/Prometheus/' $DIR/kafka-dashboards/strimzi-kafka-dashboard.json
sed -i 's/DS_PROMETHEUS/Prometheus/' $DIR/kafka-dashboards/strimzi-kafka-dashboard.json

curl -X POST http://admin:admin@${GRAFANA_ROUTE}/api/dashboards/db -d @$DIR/kafka-dashboards/strimzi-kafka-dashboard.json --header "Content-Type: application/json"

# build and POST the Zookeeper dashboard to Grafana
$DIR/kafka-dashboards/dashboard-template.sh $DIR/kafka-dashboards/strimzi-zookeeper.json > $DIR/kafka-dashboards/strimzi-zookeeper-dashboard.json

sed -i 's/${DS_PROMETHEUS}/Prometheus/' $DIR/kafka-dashboards/strimzi-zookeeper-dashboard.json
sed -i 's/DS_PROMETHEUS/Prometheus/' $DIR/kafka-dashboards/strimzi-zookeeper-dashboard.json

curl -X POST http://admin:admin@${GRAFANA_ROUTE}/api/dashboards/db -d @$DIR/kafka-dashboards/strimzi-zookeeper-dashboard.json --header "Content-Type: application/json"

curl -X "PUT" "http://${GRAFANA_ROUTE}/api/org/preferences" -H "Content-Type: application/json;charset=UTF-8" --user admin:admin --data-binary '{"theme":"","homeDashboardId":1,"timezone":"browser"}'

rm $DIR/kafka-dashboards/strimzi-kafka-dashboard.json
rm $DIR/kafka-dashboards/strimzi-zookeeper-dashboard.json
