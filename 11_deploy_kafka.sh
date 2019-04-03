#!/usr/bin/bash

set -eux
source common.sh

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

# Recover Grafana Dashboard
wget -q https://raw.githubusercontent.com/ppatierno/rh-osd-2018/master/grafana-dashboards/strimzi-kafka.json -O metrics/examples/grafana/strimzi-kafka.json
wget -q https://raw.githubusercontent.com/ppatierno/rh-osd-2018/master/grafana-dashboards/strimzi-zookeeper.json -O metrics/examples/grafana/strimzi-zookeeper.json

# Add Grafana Dashboards and Datasource
GRAFANA_ROUTE=`oc get route grafana --template='{{ .spec.host }}'`
PROMETHEUS_ROUTE=`oc get route prometheus --template='{{ .spec.host }}'`
curl -X "POST" "http://${GRAFANA_ROUTE}/api/datasources" -H "Content-Type: application/json" --user admin:admin --data-binary '{ "name":"Prometheus","type":"prometheus","access":"proxy","url":"http://'${PROMETHEUS_ROUTE}'","basicAuth":false,"isDefault":true }'
curl -X "POST" "${GRAFANA_ROUTE}/api/dashboards/db" -H "Content-Type: application/json;charset=UTF-8"  --user admin:admin --data-binary @metrics/examples/grafana/strimzi-kafka.json
curl -X "POST" "http://${GRAFANA_ROUTE}/api/dashboards/db" -H "Content-Type: application/json;charset=UTF-8"  --user admin:admin --data-binary @metrics/examples/grafana/strimzi-zookeeper.json

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
