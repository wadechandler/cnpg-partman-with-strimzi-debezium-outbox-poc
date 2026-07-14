# kafbat-ui (values only)

POC values for the upstream [Kafbat UI](https://ui.docs.kafbat.io/) Helm chart (`kafbat-ui/kafka-ui`), not a wrapper chart.

## Why not under `cnpg-outbox-poc-infra`?

That chart is **platform CRs only** (CNPG / Strimzi Kafka / Connect). Kafbat is an optional UI app, installed by `setup.sh` after Kafka is Ready — same pattern as operators (external Helm, not nested under infra CRs). Avoids dual-namespace subchart friction and keeps infra timing simple.

## Install

```bash
helm repo add kafbat-ui https://kafbat.github.io/helm-charts
helm upgrade --install kafbat-ui kafbat-ui/kafka-ui \
  --namespace kafka \
  -f ./charts/kafbat-ui/values.yaml
```

`setup.sh` does this automatically unless `SKIP_KAFBAT=1`.

## Browse

```bash
make kafbat   # port-forward svc/kafbat-ui 8080:80
# open http://127.0.0.1:8080
```

Bootstrap defaults to `poc-kafka-kafka-bootstrap.kafka.svc:9092` with display name `poc-kafka`. Override in this values file if you rename the cluster or Kafka namespace.
