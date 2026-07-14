#!/usr/bin/env bash
# Build multi-arch-capable local images and load them into KIND.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

need docker
need kind

cd "${ROOT_DIR}"

ARCH="$(uname -m)"
case "${ARCH}" in
  arm64|aarch64) PLATFORM="linux/arm64" ;;
  x86_64|amd64) PLATFORM="linux/amd64" ;;
  *) PLATFORM="linux/${ARCH}" ;;
esac

info "Building images for ${PLATFORM}"

docker build --platform "${PLATFORM}" \
  -t cnpg-outbox-poc/dlq-ingester:local \
  -f build/Dockerfile.dlq-ingester .

docker build --platform "${PLATFORM}" \
  -t cnpg-outbox-poc/event-generator:local \
  -f build/Dockerfile.event-generator .

docker build --platform "${PLATFORM}" \
  -t "${PG_IMAGE_LOCAL}" \
  -f infra/cnpg-image/Dockerfile infra/cnpg-image

# Align with charts/cnpg-outbox-poc-infra (Strimzi 0.51.0 / Kafka 4.2.0).
STRIMZI_VERSION="${STRIMZI_VERSION:-0.51.0}"
KAFKA_VERSION="${KAFKA_VERSION:-4.2.0}"
docker build --platform "${PLATFORM}" \
  --build-arg "STRIMZI_VERSION=${STRIMZI_VERSION}" \
  --build-arg "KAFKA_VERSION=${KAFKA_VERSION}" \
  -t cnpg-outbox-poc/debezium-connect:local \
  -f infra/debezium-image/Dockerfile infra/debezium-image

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  info "Loading images into KIND ${CLUSTER_NAME}"
  kind load docker-image cnpg-outbox-poc/dlq-ingester:local --name "${CLUSTER_NAME}"
  kind load docker-image cnpg-outbox-poc/event-generator:local --name "${CLUSTER_NAME}"
  kind load docker-image "${PG_IMAGE_LOCAL}" --name "${CLUSTER_NAME}"
  kind load docker-image cnpg-outbox-poc/debezium-connect:local --name "${CLUSTER_NAME}"
else
  warn "KIND cluster ${CLUSTER_NAME} not found — images built locally only"
fi
