#!/usr/bin/bash

set -eux
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/../"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${BASEDIR}/common.sh

figlet "Deploying Kafka Strimzi" | lolcat
eval "$(go env)"

export KAFKAPATH="$GOPATH/src/github.com/strimzi/strimzi-kafka-operator"
export KAFKAPRODUCER_PATH="$GOPATH/src/github.com/scholzj/kafka-test-apps"
cd $KAFKAPATH

# Apply RBAC
oc new-project ${KAFKA_NAMESPACE}
sed -i "s/namespace: .*/namespace: ${KAFKA_NAMESPACE}/" install/cluster-operator/*RoleBinding*.yaml
oc apply -f install/cluster-operator/020-RoleBinding-strimzi-cluster-operator.yaml -n ${KAFKA_NAMESPACE}
oc apply -f install/cluster-operator/031-RoleBinding-strimzi-cluster-operator-entity-operator-delegation.yaml -n ${KAFKA_NAMESPACE}
oc apply -f install/cluster-operator/032-RoleBinding-strimzi-cluster-operator-topic-operator-delegation.yaml -n ${KAFKA_NAMESPACE}

# Install Operator
oc apply -f install/cluster-operator -n ${KAFKA_NAMESPACE}
sleep 5
oc wait --for condition=ready pod -l name=strimzi-cluster-operator -n ${KAFKA_NAMESPACE} --timeout=120s

# Modify Kafka cluster & Deploy
sed -i "s/my-cluster/${KAFKA_CLUSTERNAME}/" metrics/examples/kafka/kafka-metrics.yaml
sed -i "s/100Gi/${KAFKA_PVC_SIZE}Gi/" metrics/examples/kafka/kafka-metrics.yaml
sed -i "s/my-cluster/${KAFKA_CLUSTERNAME}/" metrics/examples/kafka/kafka-connect-metrics.yaml
sed -i "s/my-connect/${KAFKA_CLUSTERNAME}/" metrics/examples/kafka/kafka-connect-metrics.yaml
oc apply -f metrics/examples/kafka/kafka-metrics.yaml -n ${KAFKA_NAMESPACE}
sleep 5
oc wait --for condition=ready pod -l strimzi.io/cluster=${KAFKA_CLUSTERNAME} -n ${KAFKA_NAMESPACE} --timeout=120s
oc apply -f metrics/examples/kafka/kafka-connect-metrics.yaml -n ${KAFKA_NAMESPACE}
sleep 5
oc wait --for condition=ready pod -l strimzi.io/kind=KafkaConnect -n ${KAFKA_NAMESPACE} --timeout=240s

# Modify Prometheus & Deploy
sed -i "s/myproject/${KAFKA_CLUSTERNAME}/" metrics/examples/prometheus/prometheus.yaml
oc apply -f metrics/examples/prometheus/prometheus.yaml -n ${KAFKA_NAMESPACE}
oc apply -f metrics/examples/prometheus/alerting-rules.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l name=prometheus -n ${KAFKA_NAMESPACE} --timeout=120s
oc apply -f metrics/examples/prometheus/alertmanager.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l name=alertmanager -n ${KAFKA_NAMESPACE} --timeout=120s

# Deploy Grafana
oc apply -f metrics/examples/grafana/grafana.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l name=grafana -n ${KAFKA_NAMESPACE} --timeout=120s

# Expose Grafana & Prometheus
oc expose svc prometheus -n ${KAFKA_NAMESPACE} || echo "Prometheus route already exists" 
oc expose svc grafana -n ${KAFKA_NAMESPACE} || echo "Grafana route already exists" 

figlet "Deploying Kafka Producer/Consumer" | lolcat

# Modify & Deploy Kafka Producer/Consumer
cd $KAFKAPRODUCER_PATH 
sed -i "s/my-cluster-kafka-bootstrap:9092/${KAFKA_CLUSTERNAME}-kafka-bootstrap:9092/" kafka-producer.yaml
sed -i "s/my-cluster-kafka-bootstrap:9092/${KAFKA_CLUSTERNAME}-kafka-bootstrap:9092/" kafka-consumer.yaml
sed -i "s/my-topic/${KAFKA_PRODUCER_TOPIC}/" kafka-producer.yaml
sed -i "s/my-topic/${KAFKA_PRODUCER_TOPIC}/" kafka-consumer.yaml
sed -i "s/\"10000\"/\"${KAFKA_PRODUCER_TIMER}\"/" kafka-producer.yaml
oc apply -f kafka-producer.yaml -n ${KAFKA_NAMESPACE}
oc apply -f kafka-consumer.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l app=kafka-consumer -n ${KAFKA_NAMESPACE} --timeout=120s

# Add Grafana Dashboards and Datasource
GRAFANA_ROUTE=`oc get route grafana --template='{{ .spec.host }}'`
PROMETHEUS_ROUTE=`oc get route prometheus --template='{{ .spec.host }}'`
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