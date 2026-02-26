# APIM Benchmark — Top-Level Makefile
# Orchestrates cluster creation, gateway deployments, and load tests.
#
# Quick start (local k3d):
#   make up              # cluster + deploy traefik
#   make test-traefik    # run k6 load test against traefik
#   make teardown        # destroy everything
#
# Full benchmark:
#   make up-all          # cluster + deploy all providers
#   make test-all        # run tests against all providers

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_PROVIDER ?= k3d
TFVARS           ?= $(CLUSTER_PROVIDER).tfvars
TF_FLAGS         ?=

PROVIDERS        ?= traefik
ALL_PROVIDERS    := traefik kong tyk gravitee envoygateway

KUBECONFIG       ?= $(HOME)/.kube/config
KUBE_CONTEXT     ?= k3d-benchmark

# ---------------------------------------------------------------------------
# Terraform helpers
# ---------------------------------------------------------------------------
define tf_init
	cd $(1) && terraform init -upgrade $(TF_FLAGS)
endef

define tf_apply
	cd $(1) && terraform apply -auto-approve -var-file=$(2) $(TF_FLAGS)
endef

define tf_destroy
	cd $(1) && terraform destroy -auto-approve -var-file=$(2) $(TF_FLAGS)
endef

define tf_validate
	cd $(1) && terraform fmt -check && terraform validate
endef

# ---------------------------------------------------------------------------
# Cluster targets
# ---------------------------------------------------------------------------
.PHONY: cluster cluster-init cluster-destroy

cluster-init: ## Initialize cluster Terraform module
	$(call tf_init,clusters)

cluster: cluster-init ## Create the k8s cluster
	$(call tf_apply,clusters,$(TFVARS))

cluster-destroy: ## Destroy the k8s cluster
	$(call tf_destroy,clusters,$(TFVARS))

# ---------------------------------------------------------------------------
# Deployment targets
# ---------------------------------------------------------------------------
.PHONY: deploy-init deploy deploy-destroy deploy-traefik deploy-kong deploy-tyk deploy-gravitee deploy-envoygateway deploy-all

deploy-init: ## Initialize deployments Terraform module
	$(call tf_init,deployments)

deploy: deploy-init ## Deploy with current tfvars (use TFVARS= to override)
	$(call tf_apply,deployments,$(TFVARS))

deploy-destroy: ## Destroy all deployments
	$(call tf_destroy,deployments,$(TFVARS))

# Helper: base providers var with all disabled
APIM_PROVIDERS_OFF := traefik={enabled=false,version="v3.6.8"},kong={enabled=false,version="3.9"},tyk={enabled=false,version="v5.8"},gravitee={enabled=false,version="4.10"},envoygateway={enabled=false,version="v1.3.0"}
APIM_PROVIDERS_ALL := traefik={enabled=true,version="v3.6.8"},kong={enabled=true,version="3.9"},tyk={enabled=true,version="v5.8"},gravitee={enabled=true,version="4.10"},envoygateway={enabled=true,version="v1.3.0"}

deploy-traefik: deploy-init ## Deploy with only Traefik enabled
	cd deployments && terraform apply -auto-approve -var-file=$(TFVARS) \
		-var='apim_providers={traefik={enabled=true,version="v3.6.8"},kong={enabled=false,version="3.9"},tyk={enabled=false,version="v5.8"},gravitee={enabled=false,version="4.10"},envoygateway={enabled=false,version="v1.3.0"}}' \
		$(TF_FLAGS)

deploy-kong: deploy-init ## Deploy with only Kong enabled
	cd deployments && terraform apply -auto-approve -var-file=$(TFVARS) \
		-var='apim_providers={traefik={enabled=false,version="v3.6.8"},kong={enabled=true,version="3.9"},tyk={enabled=false,version="v5.8"},gravitee={enabled=false,version="4.10"},envoygateway={enabled=false,version="v1.3.0"}}' \
		$(TF_FLAGS)

deploy-tyk: deploy-init ## Deploy with only Tyk enabled
	cd deployments && terraform apply -auto-approve -var-file=$(TFVARS) \
		-var='apim_providers={traefik={enabled=false,version="v3.6.8"},kong={enabled=false,version="3.9"},tyk={enabled=true,version="v5.8"},gravitee={enabled=false,version="4.10"},envoygateway={enabled=false,version="v1.3.0"}}' \
		$(TF_FLAGS)

deploy-gravitee: deploy-init ## Deploy with only Gravitee enabled
	cd deployments && terraform apply -auto-approve -var-file=$(TFVARS) \
		-var='apim_providers={traefik={enabled=false,version="v3.6.8"},kong={enabled=false,version="3.9"},tyk={enabled=false,version="v5.8"},gravitee={enabled=true,version="4.10"},envoygateway={enabled=false,version="v1.3.0"}}' \
		$(TF_FLAGS)

deploy-envoygateway: deploy-init ## Deploy with only Envoy Gateway enabled
	cd deployments && terraform apply -auto-approve -var-file=$(TFVARS) \
		-var='apim_providers={traefik={enabled=false,version="v3.6.8"},kong={enabled=false,version="3.9"},tyk={enabled=false,version="v5.8"},gravitee={enabled=false,version="4.10"},envoygateway={enabled=true,version="v1.3.0"}}' \
		$(TF_FLAGS)

deploy-all: deploy-init ## Deploy all providers
	cd deployments && terraform apply -auto-approve -var-file=$(TFVARS) \
		-var='apim_providers={$(APIM_PROVIDERS_ALL)}' \
		$(TF_FLAGS)

# ---------------------------------------------------------------------------
# Test targets
# ---------------------------------------------------------------------------
.PHONY: test test-traefik test-kong test-tyk test-gravitee test-envoygateway test-upstream test-all test-clean

test-traefik: ## Run k6 load test against Traefik
	$(MAKE) -C tests run PROVIDER=traefik

test-kong: ## Run k6 load test against Kong
	$(MAKE) -C tests run PROVIDER=kong

test-tyk: ## Run k6 load test against Tyk
	$(MAKE) -C tests run PROVIDER=tyk

test-gravitee: ## Run k6 load test against Gravitee
	$(MAKE) -C tests run PROVIDER=gravitee

test-envoygateway: ## Run k6 load test against Envoy Gateway
	$(MAKE) -C tests run PROVIDER=envoygateway

test-upstream: ## Run k6 load test against upstream (baseline)
	$(MAKE) -C tests run PROVIDER=upstream

test-all: ## Run k6 load tests against all enabled providers sequentially
	@for p in $(ALL_PROVIDERS); do \
		echo "=== Testing $$p ==="; \
		$(MAKE) -C tests run PROVIDER=$$p || true; \
		$(MAKE) -C tests wait PROVIDER=$$p || true; \
		$(MAKE) -C tests clean PROVIDER=$$p || true; \
		echo ""; \
	done

test-clean: ## Clean up all test resources
	$(MAKE) -C tests clean-all

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------
.PHONY: grafana prometheus

grafana: ## Port-forward Grafana dashboard (http://localhost:3000)
	@echo "Grafana: http://localhost:3000 (admin/admin)"
	kubectl --context=$(KUBE_CONTEXT) port-forward -n dependencies svc/grafana 3000:80

prometheus: ## Port-forward Prometheus (http://localhost:9090)
	@echo "Prometheus: http://localhost:9090"
	kubectl --context=$(KUBE_CONTEXT) port-forward -n dependencies svc/prometheus-server 9090:80

# ---------------------------------------------------------------------------
# Convenience / lifecycle
# ---------------------------------------------------------------------------
.PHONY: up up-all teardown clean status

up: cluster deploy-traefik ## Quick start: cluster + Traefik
	@echo ""
	@echo "Ready! Run 'make test-traefik' to start benchmarking."

up-all: cluster deploy-all ## Full setup: cluster + all providers
	@echo ""
	@echo "Ready! Run 'make test-all' to benchmark all providers."

teardown: deploy-destroy cluster-destroy ## Destroy deployments then cluster

clean: teardown ## Full cleanup including Terraform state
	rm -rf clusters/.terraform clusters/.terraform.lock.hcl clusters/terraform.tfstate*
	rm -rf deployments/.terraform deployments/.terraform.lock.hcl deployments/terraform.tfstate*

status: ## Show cluster and workload status
	@echo "=== Cluster ==="
	kubectl --context=$(KUBE_CONTEXT) get nodes -o wide 2>/dev/null || echo "No cluster found"
	@echo ""
	@echo "=== Namespaces ==="
	kubectl --context=$(KUBE_CONTEXT) get ns 2>/dev/null || true
	@echo ""
	@echo "=== Pods (all namespaces) ==="
	kubectl --context=$(KUBE_CONTEXT) get pods -A --sort-by=.metadata.namespace 2>/dev/null || true

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
.PHONY: validate fmt

validate: ## Validate all Terraform modules
	$(call tf_validate,clusters)
	$(call tf_validate,deployments)

fmt: ## Format all Terraform files
	terraform fmt -recursive clusters/
	terraform fmt -recursive deployments/

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
