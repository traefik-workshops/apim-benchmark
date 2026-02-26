# APIM Benchmark

Fair, reproducible performance benchmarks for API gateways and proxies on Kubernetes.

Each provider runs on dedicated, tainted nodes so there's no resource contention between competitors. Load generation also runs on isolated nodes. This ensures the only variable is the gateway itself.

**This project is still a WIP. Schema might change and suggestions are welcome.**

Originated from [TykTechnologies/tyk-performance-testing](https://github.com/TykTechnologies/tyk-performance-testing), restructured for provider-neutral, fair benchmarking.

## Supported Providers

| Middleware            | Traefik Hub        | Kong (OSS)         | Tyk (OSS)          | Gravitee           | Envoy Gateway      |
|-----------------------|--------------------|--------------------|--------------------|--------------------|--------------------|
| Baseline (no auth)    | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Rate Limiting         | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                |
| Quota                 | :white_check_mark: | via Rate Limiting   | :white_check_mark: | via Rate Limiting   | :x:                |
| Auth Token (IAC)      | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                |
| JWT HMAC (HS256)      | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                |
| JWT Keycloak (RS256)  | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Header Manipulation   | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| TLS Termination       | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                | :white_check_mark: |
| OTLP Metrics          | :white_check_mark: | :x:                | via Pump            | :x:                | :white_check_mark: |
| OTLP Logs             | :white_check_mark: | :x:                | :x:                | :x:                | :white_check_mark: |
| OTLP Traces           | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                | :white_check_mark: |

## Quick Start (local k3d)

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [k3d](https://k3d.io/) v5+
- [Terraform](https://developer.hashicorp.com/terraform/downloads) v1.5+
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- `envsubst` (part of `gettext` — usually pre-installed on Linux/macOS)

### One-command setup

```bash
make up                  # cluster + deploy Traefik + dependencies
make test-traefik        # run a baseline benchmark
make grafana             # open Grafana at http://localhost:3000 (admin/admin)
make teardown            # destroy everything
```

### Step-by-step

```bash
# 1. Create the k3d cluster with tainted nodes
make cluster

# 2. Deploy gateways + dependencies
make deploy              # Traefik only (default k3d.tfvars)
make deploy-all          # all 4 providers

# 3. Run tests
make test-traefik        # single provider
make test-all            # all providers sequentially

# 4. Cleanup
make teardown
```

## Architecture

```
clusters/    (Terraform)  →  k3d / AKS / EKS / GKE / LKE / OKE / DOKS
                             Creates node pools with taints & labels
        │
        ▼
deployments/ (Terraform)  →  Helm releases: gateways, Fortio upstreams,
                             Grafana, cert-manager, k6-operator,
                             Keycloak, OTel Collector
        │
        ▼
tests/       (Make+kubectl) → k6 ConfigMaps + CRD via kubectl
                              Fast iteration
```

### Node isolation

Each provider gets dedicated node pools (tainted with `NoSchedule`):

| Node taint          | Purpose                        |
|---------------------|--------------------------------|
| `dependencies`      | Grafana, Prometheus, k6-op     |
| `<provider>`        | Gateway pods                   |
| `<provider>-upstream` | Fortio backend               |
| `<provider>-loadgen`  | k6 test runners              |

Where `<provider>` is one of: `traefik`, `kong`, `tyk`, `gravitee`, `envoygateway`.

## Configuration

### Cluster — `clusters/k3d.tfvars`

```hcl
cluster_provider = "k3d"
apim_providers   = ["traefik", "upstream"]
```

### Deployments — `deployments/k3d.tfvars`

Controls which gateways are deployed, resource limits, and middleware. Key middleware options:

```hcl
apim_providers_middlewares = {
  auth = {
    type = "jwt_keycloak"    # disabled | jwt_hmac | jwt_keycloak | token_iac
  }
  rate_limit = { enabled = false, rate = 100, per = 1 }
  quota      = { enabled = false, rate = 1000, per = 60 }
  tls        = { enabled = true }
  headers = {
    request  = { set = { "X-Custom" = "value" }, remove = ["X-Unwanted"] }
    response = { set = { "X-Resp" = "value" }, remove = [] }
  }
  observability = {
    metrics = { enabled = true }
    logs    = { enabled = false }
    traces  = { enabled = true, ratio = "0.1" }
  }
}
```

### Tests — `tests/config/k3d.env`

```env
EXECUTOR=constant-arrival-rate
RATE=500              # requests per second
VIRTUAL_USERS=10      # pre-allocated VUs
DURATION=2            # minutes
```

For cloud benchmarks use `tests/config/cloud.env` (20k RPS, 50 VUs, 15 min).

## Make Targets

Run `make help` for the full list. Key targets:

| Target              | Description                              |
|---------------------|------------------------------------------|
| `make up`           | Cluster + deploy Traefik (quick start)   |
| `make up-all`       | Cluster + deploy all providers           |
| `make test-traefik` | Run k6 test against Traefik              |
| `make test-all`     | Benchmark all providers sequentially     |
| `make grafana`      | Port-forward Grafana (localhost:3000)    |
| `make status`       | Show cluster and pod status              |
| `make teardown`     | Destroy deployments + cluster            |
| `make validate`     | Terraform fmt + validate                 |

## Cloud Clusters

```bash
make cluster CLUSTER_PROVIDER=aks TFVARS=aks.tfvars
make deploy TFVARS=aks.tfvars
make test-all CONFIG=cloud KUBE_CONTEXT=benchmark
```

### Connecting to managed clusters

```
# AKS
az aks get-credentials --resource-group "pt-westus" --name "pt-westus"

# EKS
aws eks --region "us-west-1" update-kubeconfig --name "pt-us-west-1"

# GKE
gcloud container clusters get-credentials pt-us-west1-a \
   --zone us-west1-a --project performance-testing
```

### Self-managed cluster requirements

Your cluster needs nodes labeled for each provider you want to test:

```bash
kubectl label nodes node-01 node=dependencies
kubectl label nodes node-02 node=traefik
kubectl label nodes node-03 node=traefik-upstream
kubectl label nodes node-04 node=traefik-loadgen
# ... repeat for kong, tyk, gravitee as needed
```
