#!/usr/bin/env bash
# Open interactive psql against the CNPG primary in the POC cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

need kubectl

POD="$(kubectl -n "${APP_NS}" get pod -l cnpg.io/cluster=cnpg-outbox-db,role=primary -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${POD}" ]] || error "primary pod not found for cnpg-outbox-db"

PASS="$(kubectl -n "${APP_NS}" get secret cnpg-outbox-db-app -o jsonpath='{.data.password}' | base64 -d)"
USER_NAME="$(kubectl -n "${APP_NS}" get secret cnpg-outbox-db-app -o jsonpath='{.data.username}' | base64 -d)"

info "Connecting to ${POD} as ${USER_NAME} (database app). Ctrl-D to exit."
exec kubectl -n "${APP_NS}" exec -it "${POD}" -- env PGPASSWORD="${PASS}" \
  psql -h 127.0.0.1 -U "${USER_NAME}" -d app
