.PHONY: help check up down verify psql generate build-images deploy-apps render-infra kafbat vulncheck test

CLUSTER_NAME ?= cnpg-outbox-poc
ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

help:
	@echo "Targets:"
	@echo "  make check         - verify required tools"
	@echo "  make up            - build images + KIND setup (CNPG/Strimzi/Debezium/apps)"
	@echo "  make down          - delete KIND cluster"
	@echo "  make verify        - smoke checks"
	@echo "  make psql          - interactive psql on CNPG primary"
	@echo "  make generate      - publish sample DLQ events (ARGS='...')"
	@echo "  make kafbat        - port-forward Kafbat UI (http://127.0.0.1:8080)"
	@echo "  make build-images  - build/load Go + Debezium images into KIND"
	@echo "  make deploy-apps   - helm upgrade app chart"
	@echo "  make render-infra  - helm template platform CRs (read-only; not a second source)"
	@echo "  make test          - go test ./..."
	@echo "  make vulncheck     - govulncheck ./..."

check:
	@command -v kind >/dev/null
	@command -v kubectl >/dev/null
	@command -v helm >/dev/null
	@command -v docker >/dev/null
	@command -v go >/dev/null
	@echo "tools OK"

test:
	go test ./...

vulncheck:
	go run golang.org/x/vuln/cmd/govulncheck@latest ./...

build-images:
	./infra/scripts/build-images.sh

deploy-apps:
	helm upgrade --install cnpg-outbox-poc ./charts/cnpg-outbox-poc \
		--namespace cnpg-outbox-poc --create-namespace --wait --timeout 180s

# On-demand flat view of platform CRs. Do not commit the output; edit chart values/templates instead.
render-infra:
	helm template cnpg-outbox-poc-infra ./charts/cnpg-outbox-poc-infra \
		--namespace cnpg-outbox-poc

up: check build-images
	./infra/scripts/setup.sh

down:
	./infra/scripts/teardown.sh cluster

verify:
	./infra/scripts/verify.sh

psql:
	./infra/scripts/psql.sh

# Long-lived local browse of Kafka topics (does not run during make up / setup.sh).
kafbat:
	@echo "Kafbat UI → http://127.0.0.1:8080  (Ctrl-C to stop)"
	kubectl --context kind-$(CLUSTER_NAME) -n kafka port-forward svc/kafbat-ui 8080:80

generate:
	go run ./cmd/event-generator $(ARGS)
