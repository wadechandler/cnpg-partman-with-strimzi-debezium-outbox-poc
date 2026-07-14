#!/usr/bin/env bash
# Create KIND cluster and install CNPG, Strimzi, Kafka topics, Debezium, SQL init.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

# Pin Strimzi operator to a release that supports Kafka 4.2 (default in chart values).
STRIMZI_OPERATOR_VERSION="${STRIMZI_OPERATOR_VERSION:-0.51.0}"
INFRA_CHART="${ROOT_DIR}/charts/cnpg-outbox-poc-infra"
INFRA_RELEASE="${INFRA_RELEASE:-cnpg-outbox-poc-infra}"

need kind
need kubectl
need helm
need docker

cd "${ROOT_DIR}"

# ---------------------------------------------------------------------------
# Step 0: KIND cluster
# ---------------------------------------------------------------------------
info "Step 0: KIND cluster (${CLUSTER_NAME})"
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  info "Cluster ${CLUSTER_NAME} already exists — skipping create"
else
  kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT_DIR}/infra/kind-config.yaml"
fi
kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null

# ---------------------------------------------------------------------------
# Step 1: Namespaces
# ---------------------------------------------------------------------------
info "Step 1: Namespaces"
kubectl create namespace "${APP_NS}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "${KAFKA_NS}" --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Step 2: Custom images are expected from make build-images / build-images.sh
# ---------------------------------------------------------------------------
info "Step 2: Ensure custom images exist in KIND"
for img in "${PG_IMAGE_LOCAL}" cnpg-outbox-poc/debezium-connect:local cnpg-outbox-poc/dlq-ingester:local; do
  if ! docker image inspect "${img}" >/dev/null 2>&1; then
    error "missing image ${img} — run: make build-images"
  fi
  kind load docker-image "${img}" --name "${CLUSTER_NAME}"
done

# ---------------------------------------------------------------------------
# Step 3: CloudNativePG operator (Cluster + SQL ConfigMap come from infra chart)
# ---------------------------------------------------------------------------
info "Step 3: CloudNativePG operator"
helm_repo_add cnpg https://cloudnative-pg.github.io/charts
helm repo update cnpg >/dev/null
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace "${CNPG_NS}" \
  --create-namespace \
  --wait --timeout 180s
wait_for_crd clusters.postgresql.cnpg.io 120

# ---------------------------------------------------------------------------
# Step 4: Strimzi operator (+ CRDs) before Kafka / Connect CRs
# ---------------------------------------------------------------------------
info "Step 4: Strimzi Kafka operator (${STRIMZI_OPERATOR_VERSION})"
helm_repo_add strimzi https://strimzi.io/charts/
helm repo update strimzi >/dev/null
helm upgrade --install strimzi strimzi/strimzi-kafka-operator \
  --namespace "${KAFKA_NS}" \
  --version "${STRIMZI_OPERATOR_VERSION}" \
  --wait --timeout 180s

# Helm may not upgrade Strimzi CRDs; apply release CRDs explicitly when upgrading.
info "Applying Strimzi CRDs ${STRIMZI_OPERATOR_VERSION}"
kubectl apply -f "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${STRIMZI_OPERATOR_VERSION}/strimzi-crds-${STRIMZI_OPERATOR_VERSION}.yaml"

wait_for_crd kafkas.kafka.strimzi.io 120
wait_for_crd kafkanodepools.kafka.strimzi.io 120
wait_for_crd kafkatopics.kafka.strimzi.io 120
wait_for_crd kafkaconnects.kafka.strimzi.io 120
wait_for_crd kafkaconnectors.kafka.strimzi.io 120

# ---------------------------------------------------------------------------
# Step 5: Platform CRs via infra Helm chart (SQL ConfigMap + CNPG + Kafka + Debezium)
# ---------------------------------------------------------------------------
info "Step 5: Infra Helm chart (${INFRA_RELEASE})"
# Chart renders bootstrap SQL ConfigMap (files/sql/00*.sql) + Cluster + Kafka/Connect.
# No helm --wait: CNPG/Kafka/Connect readiness is checked explicitly below.
helm upgrade --install "${INFRA_RELEASE}" "${INFRA_CHART}" \
  --namespace "${APP_NS}" \
  --set "namespaces.app=${APP_NS}" \
  --set "namespaces.kafka=${KAFKA_NS}"

kubectl -n "${APP_NS}" wait --for=condition=Ready "cluster/cnpg-outbox-db" --timeout=300s

# Copy superuser password into kafka namespace for Debezium connector.
info "Syncing DB secret for Debezium"
SU_USER="$(kubectl -n "${APP_NS}" get secret cnpg-outbox-db-superuser -o jsonpath='{.data.username}' | base64 -d)"
SU_PASS="$(kubectl -n "${APP_NS}" get secret cnpg-outbox-db-superuser -o jsonpath='{.data.password}' | base64 -d)"
kubectl -n "${KAFKA_NS}" create secret generic cnpg-outbox-db-superuser \
  --from-literal=username="${SU_USER}" \
  --from-literal=password="${SU_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${KAFKA_NS}" wait kafka/poc-kafka --for=condition=Ready --timeout=300s || {
  warn "Kafka may still be starting — check: kubectl get kafka -n ${KAFKA_NS}"
}

# ---------------------------------------------------------------------------
# Step 5b: Kafbat UI (optional browse of topics; not a long-lived port-forward)
# ---------------------------------------------------------------------------
if [[ "${SKIP_KAFBAT:-0}" != "1" ]]; then
  info "Step 5b: Kafbat UI (kafka-ui)"
  helm_repo_add kafbat-ui https://kafbat.github.io/helm-charts
  helm repo update kafbat-ui >/dev/null
  helm upgrade --install kafbat-ui kafbat-ui/kafka-ui \
    --namespace "${KAFKA_NS}" \
    -f "${ROOT_DIR}/charts/kafbat-ui/values.yaml" \
    --wait --timeout 180s || warn "Kafbat UI install issue — check: kubectl -n ${KAFKA_NS} get deploy,svc -l app.kubernetes.io/name=kafka-ui"
  info "Browse topics later with: make kafbat  (http://127.0.0.1:8080)"
else
  info "SKIP_KAFBAT=1 — skipping Kafbat UI"
fi

kubectl -n "${KAFKA_NS}" wait kafkaconnect/debezium-connect --for=condition=Ready --timeout=300s || \
  warn "Debezium Connect still starting"

# Patch connector password from synced secret
PGPASSWORD="$(kubectl -n "${KAFKA_NS}" get secret cnpg-outbox-db-superuser -o jsonpath='{.data.password}' | base64 -d)"
export PGPASSWORD
kubectl -n "${KAFKA_NS}" annotate kafkaconnector replay-outbox-connector \
  force-password-sync="$(date +%s)" --overwrite >/dev/null 2>&1 || true
kubectl -n "${KAFKA_NS}" patch kafkaconnector replay-outbox-connector --type merge -p \
  "{\"spec\":{\"config\":{\"database.password\":\"${PGPASSWORD}\"}}}"

# ---------------------------------------------------------------------------
# Step 6: App chart
# ---------------------------------------------------------------------------
info "Step 6: Helm chart (apps)"
if [[ "${SKIP_APPS:-0}" != "1" ]]; then
  helm upgrade --install cnpg-outbox-poc "${ROOT_DIR}/charts/cnpg-outbox-poc" \
    --namespace "${APP_NS}" \
    --wait --timeout 180s || warn "App chart install issue — check pods"
else
  info "SKIP_APPS=1 — skipping app deploy"
fi

info "Setup complete. Try: make generate && make psql && make verify"
info "Browse Kafka topics: make kafbat  (http://127.0.0.1:8080)"
