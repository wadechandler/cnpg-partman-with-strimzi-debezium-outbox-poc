{{/*
Topic name prefix for KafkaTopic metadata names and Debezium routing.
*/}}
{{- define "cnpg-outbox-poc-infra.topicPrefix" -}}
{{- .Values.global.topicPrefix -}}
{{- end -}}

{{/*
In-cluster Kafka bootstrap for KafkaConnect.
*/}}
{{- define "cnpg-outbox-poc-infra.kafkaBootstrap" -}}
{{- if .Values.kafka.bootstrapServers -}}
{{- .Values.kafka.bootstrapServers -}}
{{- else -}}
{{- printf "%s-kafka-bootstrap.%s.svc:9092" .Values.kafka.clusterName .Values.namespaces.kafka -}}
{{- end -}}
{{- end -}}

{{/*
Postgres host for Debezium (injectable separate DB cluster).
*/}}
{{- define "cnpg-outbox-poc-infra.debeziumHostname" -}}
{{- if .Values.debezium.database.hostname -}}
{{- .Values.debezium.database.hostname -}}
{{- else -}}
{{- .Values.postgres.serviceHost -}}
{{- end -}}
{{- end -}}

{{/*
Debezium topic.prefix (CDC internal topics).
*/}}
{{- define "cnpg-outbox-poc-infra.debeziumTopicPrefix" -}}
{{- if .Values.debezium.topicPrefix -}}
{{- .Values.debezium.topicPrefix -}}
{{- else -}}
{{- printf "%s.outbox" .Values.global.topicPrefix -}}
{{- end -}}
{{- end -}}

{{/*
Final retry topic after RegexRouter SMT.
*/}}
{{- define "cnpg-outbox-poc-infra.retryTopic" -}}
{{- if .Values.debezium.retryTopic -}}
{{- .Values.debezium.retryTopic -}}
{{- else -}}
{{- printf "%s.events.retry" .Values.global.topicPrefix -}}
{{- end -}}
{{- end -}}

{{/*
Debezium heartbeat topic: {topic.heartbeat.prefix}.{topic.prefix}
*/}}
{{- define "cnpg-outbox-poc-infra.heartbeatTopic" -}}
{{- $hbPrefix := .Values.debezium.heartbeatTopicPrefix | default "__debezium-heartbeat" -}}
{{- printf "%s.%s" $hbPrefix (include "cnpg-outbox-poc-infra.debeziumTopicPrefix" .) -}}
{{- end -}}
