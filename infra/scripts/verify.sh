#!/usr/bin/env bash
# Smoke-check POC resources.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

need kubectl

PASS=0
FAIL=0

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    info "PASS: ${name}"
    PASS=$((PASS + 1))
  else
    warn "FAIL: ${name}"
    FAIL=$((FAIL + 1))
  fi
}

ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${ctx}" == "kind-${CLUSTER_NAME}" ]]; then
  info "PASS: KIND context"
  PASS=$((PASS + 1))
else
  warn "FAIL: KIND context (got '${ctx}')"
  FAIL=$((FAIL + 1))
fi

phase="$(kubectl -n "${APP_NS}" get cluster cnpg-outbox-db -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "${phase}" == "Cluster in healthy state" ]]; then
  info "PASS: CNPG cluster healthy (${phase})"
  PASS=$((PASS + 1))
else
  warn "FAIL: CNPG cluster (phase='${phase}')"
  FAIL=$((FAIL + 1))
fi

ready="$(kubectl -n "${KAFKA_NS}" get kafka poc-kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
if [[ "${ready}" == "True" ]]; then
  info "PASS: Kafka Ready"
  PASS=$((PASS + 1))
else
  warn "FAIL: Kafka Ready"
  FAIL=$((FAIL + 1))
fi

check "retry-dlq topic" kubectl -n "${KAFKA_NS}" get kafkatopic cnpg-outbox-poc.events.retry-dlq

dc="$(kubectl -n "${KAFKA_NS}" get kafkaconnect debezium-connect -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
if [[ "${dc}" == "True" ]]; then
  info "PASS: Debezium Connect Ready"
  PASS=$((PASS + 1))
else
  warn "FAIL: Debezium Connect Ready"
  FAIL=$((FAIL + 1))
fi

check "dlq-ingester running" kubectl -n "${APP_NS}" get deploy dlq-ingester

printf '\nSummary: %s passed, %s failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
