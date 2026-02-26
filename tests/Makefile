# APIM Benchmark — Test Runner Makefile
# Applies k6 test manifests via kubectl. No Terraform needed.
#
# Usage:
#   make run PROVIDER=traefik          # Run test against Traefik
#   make run PROVIDER=kong             # Run test against Kong
#   make wait PROVIDER=traefik         # Wait for test to complete
#   make clean PROVIDER=traefik        # Remove test resources
#   make clean-all                     # Remove all test resources

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROVIDER     ?= traefik
CONFIG       ?= k3d
KUBE_CONTEXT ?= k3d-benchmark

SCRIPTS_DIR  := $(CURDIR)/k6/scripts
MANIFESTS_DIR := $(CURDIR)/k6/manifests
CONFIG_DIR   := $(CURDIR)/config

# Provider → service name mapping
SERVICE_NAME_traefik  := traefik
SERVICE_PORT_traefik  := 80
SERVICE_NAME_kong     := kong-gateway-proxy
SERVICE_PORT_kong     := 80
SERVICE_NAME_tyk      := gateway-svc-tyk-tyk-gateway
SERVICE_PORT_tyk      := 8080
SERVICE_NAME_gravitee := gravitee-apim-gateway
SERVICE_PORT_gravitee := 82
SERVICE_NAME_envoygateway := envoy-gateway-proxy
SERVICE_PORT_envoygateway := 8080
SERVICE_NAME_upstream     := fortio
SERVICE_PORT_upstream     := 8080

SERVICE_NAME = $(SERVICE_NAME_$(PROVIDER))
SERVICE_PORT = $(SERVICE_PORT_$(PROVIDER))

KUBECTL := kubectl --context=$(KUBE_CONTEXT)

# ---------------------------------------------------------------------------
# Load test configuration from env file
# ---------------------------------------------------------------------------
include $(CONFIG_DIR)/$(CONFIG).env
export

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
.PHONY: run configmaps k6-test wait clean clean-all help

run: configmaps k6-test ## Deploy ConfigMaps + k6 test for PROVIDER
	@echo ""
	@echo "Test submitted for $(PROVIDER). Use 'make wait PROVIDER=$(PROVIDER)' to watch progress."

configmaps: ## Apply k6 script ConfigMaps for PROVIDER
	@echo "==> Creating ConfigMaps for $(PROVIDER)..."
	@$(KUBECTL) create namespace $(PROVIDER) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(KUBECTL) create configmap test-script-configmap \
		--from-file=script.js=$(SCRIPTS_DIR)/test.js \
		-n $(PROVIDER) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(KUBECTL) create configmap tests-configmap \
		--from-file=tests.js=$(SCRIPTS_DIR)/helpers/tests.js \
		-n $(PROVIDER) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(KUBECTL) create configmap scenarios-configmap \
		--from-file=scenarios.js=$(SCRIPTS_DIR)/helpers/scenarios.js \
		-n $(PROVIDER) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(KUBECTL) create configmap auth-configmap \
		--from-file=auth.js=$(SCRIPTS_DIR)/auth/$(PROVIDER).js \
		-n $(PROVIDER) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@echo "    ConfigMaps applied."

k6-test: ## Apply k6 test CRD for PROVIDER
	@echo "==> Submitting k6 test for $(PROVIDER)..."
	@export PROVIDER=$(PROVIDER) \
		SERVICE_NAME=$(SERVICE_NAME) \
		SERVICE_PORT=$(SERVICE_PORT) && \
		envsubst < $(MANIFESTS_DIR)/k6-test.yaml | $(KUBECTL) apply -f -
	@echo "    k6 test resource created."

wait: ## Wait for the k6 test to complete
	@echo "Watching k6 test pods in namespace $(PROVIDER)..."
	@$(KUBECTL) get pods -n $(PROVIDER) -l app=k6 -w 2>/dev/null || \
		$(KUBECTL) get pods -n $(PROVIDER) -w

logs: ## Tail logs from k6 runner pods
	@$(KUBECTL) logs -n $(PROVIDER) -l runner=true -f --tail=50 2>/dev/null || \
		echo "No runner pods found yet."

clean: ## Delete k6 test resources for PROVIDER
	@echo "==> Cleaning test resources for $(PROVIDER)..."
	-@$(KUBECTL) delete testrun test -n $(PROVIDER) 2>/dev/null
	-@$(KUBECTL) delete configmap test-script-configmap tests-configmap scenarios-configmap auth-configmap -n $(PROVIDER) 2>/dev/null
	@echo "    Cleaned."

clean-all: ## Delete test resources for all providers
	@for p in traefik kong tyk gravitee envoygateway upstream; do \
		echo "==> Cleaning $$p..."; \
		$(KUBECTL) delete testrun test -n $$p 2>/dev/null || true; \
		$(KUBECTL) delete configmap test-script-configmap tests-configmap scenarios-configmap auth-configmap -n $$p 2>/dev/null || true; \
	done
	@echo "All test resources cleaned."

status: ## Show test pod status for PROVIDER
	@$(KUBECTL) get pods -n $(PROVIDER) -l app=k6 2>/dev/null || \
		$(KUBECTL) get pods -n $(PROVIDER)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
