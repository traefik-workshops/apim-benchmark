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

k6-test: configmaps ## Apply k6 test CRD for PROVIDER
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

summary: ## Extract the JSON summary block from the completed runner log
	@pod=$$($(KUBECTL) get pods -n $(PROVIDER) --no-headers 2>/dev/null | awk '/test-1.*Completed/{print $$1; exit}'); \
	if [ -z "$$pod" ]; then echo "No completed runner pod in namespace $(PROVIDER)"; exit 1; fi; \
	$(KUBECTL) logs -n $(PROVIDER) "$$pod" 2>/dev/null | \
		awk '/===== K6_SUMMARY_BEGIN =====/,/===== K6_SUMMARY_END =====/' | \
		grep -v '^===== K6_SUMMARY_'

validate-test: ## PROVIDER=<x> — 30s probe + assert pod placement + assert metrics
	@bash -c 'set -euo pipefail; \
		P="$(PROVIDER)"; CTX="$(KUBE_CONTEXT)"; \
		echo "==> Validate-test for PROVIDER=$$P"; \
		$(MAKE) clean PROVIDER=$$P >/dev/null 2>&1 || true; \
		DURATION=1 RATE=50 KEY_COUNT=10 AUTH_TYPE=disabled \
			$(MAKE) run PROVIDER=$$P CONFIG=$(CONFIG) >/dev/null; \
		echo "==> Waiting for test to complete (~90s)..."; \
		for i in $$(seq 1 40); do \
			stage=$$(kubectl --context=$$CTX get testrun test -n $$P -o jsonpath="{.status.stage}" 2>/dev/null || echo ""); \
			[ "$$stage" = "finished" ] && break; \
			sleep 5; \
		done; \
		if [ "$$stage" != "finished" ]; then echo "FAIL: test did not finish (stage=$$stage)"; exit 1; fi; \
		echo "==> Asserting pod placements..."; \
		ok=1; \
		if [ "$$P" != "upstream" ]; then \
			gw=$$(kubectl --context=$$CTX get pods -n $$P -o jsonpath="{range .items[?(@.metadata.labels.app\\.kubernetes\\.io/name==\"$$P\")]}{.spec.nodeName}{\"\\n\"}{end}" 2>/dev/null | head -1); \
			expected=$$(kubectl --context=$$CTX get nodes -l node=$$P -o name 2>/dev/null | sed "s#node/##" | head -1); \
			if [ -z "$$gw" ] || [ "$$gw" != "$$expected" ]; then \
				echo "  [WARN] gateway pod on $${gw:-?}, expected $${expected:-?} (node=$$P)"; \
			else \
				echo "  [OK]   gateway on $$gw"; \
			fi; \
		fi; \
		runner_node=$$(kubectl --context=$$CTX get pods -n $$P -l runner=true -o jsonpath="{.items[0].spec.nodeName}" 2>/dev/null); \
		expected_loadgen=$$(kubectl --context=$$CTX get nodes -l node=$$P-loadgen -o name 2>/dev/null | sed "s#node/##" | head -1); \
		if [ -z "$$runner_node" ] || [ "$$runner_node" != "$$expected_loadgen" ]; then \
			echo "  [FAIL] runner on $${runner_node:-?}, expected $${expected_loadgen:-?} (node=$$P-loadgen)"; ok=0; \
		else \
			echo "  [OK]   runner on $$runner_node"; \
		fi; \
		echo "==> Asserting metrics in Prometheus..."; \
		kubectl --context=$$CTX -n dependencies port-forward svc/prometheus-kube-prometheus-prometheus 19090:9090 >/dev/null 2>&1 & \
		PF=$$!; sleep 3; \
		reqs=$$(curl -s "http://localhost:19090/api/v1/query?query=max(max_over_time(k6_http_reqs_total%7Btestid%3D%22$$P%22%7D%5B5m%5D))" | python3 -c "import json,sys;r=json.load(sys.stdin)[\"data\"][\"result\"];print(r[0][\"value\"][1] if r else \"0\")"); \
		fail=$$(curl -s "http://localhost:19090/api/v1/query?query=max(max_over_time(k6_http_req_failed_rate%7Btestid%3D%22$$P%22%7D%5B5m%5D))" | python3 -c "import json,sys;r=json.load(sys.stdin)[\"data\"][\"result\"];print(r[0][\"value\"][1] if r else \"0\")"); \
		kill $$PF 2>/dev/null || true; \
		if [ "$$(printf %.0f $$reqs)" -lt "100" ]; then \
			echo "  [FAIL] k6_http_reqs_total{testid=$$P} = $$reqs (expected >= 100)"; ok=0; \
		else \
			echo "  [OK]   reqs=$$reqs fail_rate=$$fail"; \
		fi; \
		if [ "$$(printf %.0f $$(echo "$$fail * 100" | bc -l))" -gt "0" ]; then \
			echo "  [FAIL] k6_http_req_failed_rate{testid=$$P} = $$fail"; ok=0; \
		fi; \
		[ $$ok -eq 1 ] && echo "==> validate-test PASS" || (echo "==> validate-test FAIL"; exit 1)'

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
