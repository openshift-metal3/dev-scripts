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
oc wait --for condition=ready pod -l name=${KAFKA_NAMESPACE}-cluster-operator -n ${KAFKA_NAMESPACE} --timeout=120s

# Modify Kafka cluster & Deploy
sed -i "s/my-cluster/${KAFKA_CLUSTERNAME}/" metrics/examples/kafka/kafka-metrics.yaml
sed -i "s/my-cluster/${KAFKA_CLUSTERNAME}/" metrics/examples/kafka/kafka-connect-metrics.yaml
oc apply -f metrics/examples/kafka/kafka-metrics.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l strimzi.io/cluster=${KAFKA_CLUSTERNAME} -n ${KAFKA_NAMESPACE} --timeout=120s
oc apply -f metrics/examples/kafka/kafka-connect-metrics.yaml -n ${KAFKA_NAMESPACE}
oc wait --for condition=ready pod -l strimzi.io/kind=KafkaConnect -n ${KAFKA_NAMESPACE} --timeout=120s

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
