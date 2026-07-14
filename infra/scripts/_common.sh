#!/usr/bin/env bash
# Shared helpers for infra scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-cnpg-outbox-poc}"
KAFKA_NS="${KAFKA_NS:-kafka}"
CNPG_NS="${CNPG_NS:-cnpg-system}"
APP_NS="${APP_NS:-cnpg-outbox-poc}"
PG_IMAGE_LOCAL="${PG_IMAGE_LOCAL:-cnpg-outbox-poc-pg:17.5-partman}"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
error() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || error "missing required tool: $1"
}

wait_for_crd() {
  local crd="$1"
  local timeout="${2:-120}"
  local i=0
  info "Waiting for CRD ${crd}..."
  until kubectl get crd "${crd}" >/dev/null 2>&1; do
    i=$((i + 1))
    if [[ "${i}" -ge "${timeout}" ]]; then
      error "timed out waiting for CRD ${crd}"
    fi
    sleep 1
  done
}

wait_for_deployment() {
  local ns="$1"
  local name="$2"
  local timeout="${3:-180s}"
  kubectl -n "${ns}" rollout status "deployment/${name}" --timeout="${timeout}"
}

helm_repo_add() {
  local name="$1"
  local url="$2"
  if helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "${name}"; then
    info "Helm repo ${name} already present"
  else
    helm repo add "${name}" "${url}"
  fi
}
