#!/usr/bin/env bash
# Tear down POC KIND cluster (and optionally only app resources).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

need kind

MODE="${1:-cluster}"

case "${MODE}" in
  apps)
    need helm
    need kubectl
    info "Uninstalling app chart from ${APP_NS}"
    helm uninstall cnpg-outbox-poc -n "${APP_NS}" 2>/dev/null || true
    info "Uninstalling Kafbat UI from ${KAFKA_NS}"
    helm uninstall kafbat-ui -n "${KAFKA_NS}" 2>/dev/null || true
    ;;
  cluster|*)
    if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
      info "Deleting KIND cluster ${CLUSTER_NAME}"
      kind delete cluster --name "${CLUSTER_NAME}"
    else
      info "Cluster ${CLUSTER_NAME} not found — nothing to delete"
    fi
    ;;
esac
