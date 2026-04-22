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
# CLUSTER_PROVIDER selects which clusters/<dir>/ terraform module to run.
# For k3d, the module auto-loads clusters/k3d/terraform.tfvars. Cloud modules
# do the same.
#
# DEPLOY_TFVARS picks the deployments/ tfvars file. For k3d we use local.tfvars
# (context=k3d-benchmark); anything else uses cloud.tfvars (context=gke-benchmark
# by default — override with -var kubernetes_config_context=<ctx>).
CLUSTER_PROVIDER ?= k3d
CLUSTER_DIR      := clusters/$(CLUSTER_PROVIDER)
DEPLOY_TFVARS    ?= $(if $(filter k3d,$(CLUSTER_PROVIDER)),local.tfvars,cloud.tfvars)
TF_FLAGS         ?=

# Providers enabled by default in the tfvars file. If you need to deploy a
# subset, override apim_providers via -var='apim_providers={...}' using the
# values already pinned in local.tfvars/cloud.tfvars.
ALL_PROVIDERS    := traefik kong tyk gravitee envoygateway upstream

KUBECONFIG       ?= $(HOME)/.kube/config
KUBE_CONTEXT     ?= k3d-benchmark

# ---------------------------------------------------------------------------
# Cluster targets
# ---------------------------------------------------------------------------
.PHONY: cluster cluster-init cluster-destroy

cluster-init: ## terraform init for clusters/$(CLUSTER_PROVIDER)
	cd $(CLUSTER_DIR) && terraform init -upgrade $(TF_FLAGS)

cluster: cluster-init ## Create the k8s cluster (uses $(CLUSTER_DIR)/terraform.tfvars)
	cd $(CLUSTER_DIR) && terraform apply -auto-approve $(TF_FLAGS)

cluster-destroy: ## Destroy the k8s cluster
	cd $(CLUSTER_DIR) && terraform destroy -auto-approve $(TF_FLAGS)

# ---------------------------------------------------------------------------
# Deployment targets
# ---------------------------------------------------------------------------
.PHONY: deploy-init deploy deploy-destroy

deploy-init: ## Initialize deployments Terraform module
	cd deployments && terraform init -upgrade $(TF_FLAGS)

deploy: deploy-init ## Deploy using $(DEPLOY_TFVARS) — all 5 providers per tfvars
	cd deployments && terraform apply -auto-approve -var-file=$(DEPLOY_TFVARS) $(TF_FLAGS)

deploy-destroy: ## Destroy all deployments
	cd deployments && terraform destroy -auto-approve -var-file=$(DEPLOY_TFVARS) $(TF_FLAGS)

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
# Convenience / lifecycle
# ---------------------------------------------------------------------------
.PHONY: up up-all teardown clean status

up: cluster deploy ## Quick start: cluster + all providers per tfvars
	@echo ""
	@echo "Ready! Run 'make test-all' to benchmark all enabled providers."

teardown: deploy-destroy cluster-destroy ## Destroy deployments then cluster

clean: teardown ## Full cleanup including Terraform state
	rm -rf $(CLUSTER_DIR)/.terraform $(CLUSTER_DIR)/.terraform.lock.hcl $(CLUSTER_DIR)/terraform.tfstate*
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
	cd $(CLUSTER_DIR) && terraform fmt -check && terraform validate
	cd deployments && terraform fmt -check && terraform validate

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
