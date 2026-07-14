# Strimzi KafkaConnect image with Debezium PostgreSQL connector.
# Strimzi does NOT ship Debezium plugins; Connect loads jars from /opt/kafka/plugins.
# We copy the Postgres connector from the official Debezium Connect image into a
# Strimzi Kafka base so KafkaConnect / KafkaConnector CRs still manage the runtime.
#
# Keep in sync with charts/cnpg-outbox-poc-infra values + setup.sh STRIMZI_OPERATOR_VERSION.
# Strimzi 0.51.0 ships Kafka 4.2.0 (quay.io/strimzi/kafka:0.51.0-kafka-4.2.0).
ARG STRIMZI_VERSION=0.51.0
ARG KAFKA_VERSION=4.2.0
ARG DEBEZIUM_CONNECT_TAG=2.7

FROM quay.io/debezium/connect:${DEBEZIUM_CONNECT_TAG} AS debezium

FROM quay.io/strimzi/kafka:${STRIMZI_VERSION}-kafka-${KAFKA_VERSION}

USER root:root
RUN mkdir -p /opt/kafka/plugins/debezium
COPY --from=debezium /kafka/connect/debezium-connector-postgres /opt/kafka/plugins/debezium/debezium-connector-postgres
# Strimzi Kafka images run as UID 1001 (non-root). Upstream Debezium-on-Strimzi
# examples hardcode USER 1001 after installing plugins as root.
USER 1001
