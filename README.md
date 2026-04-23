# APIM Benchmark

Fair, reproducible performance benchmarks for API gateways and proxies on Kubernetes.

Each provider runs on dedicated, tainted nodes so there's no resource contention between competitors — gateway, upstream, and load generator each get their own pool. Everything around the gateway (cluster type, dependencies, load generator, upstream backend, observability) is held identical. The gateway itself is the only variable.

**This project is still a WIP. Schema may change and suggestions are welcome.**

Originated from [TykTechnologies/tyk-performance-testing](https://github.com/TykTechnologies/tyk-performance-testing), restructured for provider-neutral, fair benchmarking.

## Supported Providers

| Middleware            | Traefik Hub        | Kong (OSS)         | Tyk (OSS)          | Gravitee           | Envoy Gateway      |
|-----------------------|--------------------|--------------------|--------------------|--------------------|--------------------|
| Baseline (no auth)    | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Rate Limiting         | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                |
| Quota                 | :white_check_mark: | via Rate Limiting  | :white_check_mark: | via Rate Limiting  | :x:                |
| Auth Token (IAC)      | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                |
| JWT HMAC (HS256)      | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                |
| JWT Keycloak (RS256)  | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Header Manipulation   | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| TLS Termination       | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                | :white_check_mark: |
| OTLP Metrics          | :white_check_mark: | :x:                | via Pump           | :x:                | :white_check_mark: |
| OTLP Logs             | :white_check_mark: | :x:                | :x:                | :x:                | :white_check_mark: |
| OTLP Traces           | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x:                | :white_check_mark: |

When comparing providers, **only use rows where every compared provider is ✓**. Substituting "via Rate Limiting" for Quota, for example, is not apples-to-apples.

## Pinned versions

All chart and image versions are pinned to 2026-04 latest-stable. Chart versions live in [deployments/versions.tf](deployments/versions.tf) (single source of truth); image tags are in [deployments/local.tfvars](deployments/local.tfvars) / `cloud.tfvars` under `apim_providers.<x>.version`.

| Component      | Chart  | Image         |
|----------------|--------|---------------|
| Traefik Hub    | 39.0.8 | v3.19.4       |
| Kong OSS       | 0.24.0 | 3.9.1         |
| Tyk OSS        | 5.1.1  | v5.11.0       |
| Gravitee       | 4.11.4 | 4.11.4        |
| Envoy Gateway  | 1.7.2  | v1.7.2        |

## Quick Start (local k3d)

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [k3d](https://k3d.io/) v5+
- [Terraform](https://developer.hashicorp.com/terraform/downloads) v1.5+
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- `envsubst` (part of `gettext` — usually pre-installed on Linux/macOS)

### Required external state

Two sibling checkouts must live next to this repo (absolute and `../../../..`-relative paths in the Helm chart references depend on the layout):

```
<parent>/
  apim-benchmark/                  # this repo
  terraform-demo-modules/          # https://github.com/traefik-workshops/terraform-demo-modules
  traefik-demo-resources/          # supplies the local Keycloak + dns-traefiker charts
```

### Required secrets

Set `TF_VAR_traefik_hub_token` before running `make deploy` if you want Traefik Hub features (API auth, rate-limits, managed applications). Without it, Traefik deploys as OSS and the Hub-backed middleware rows in the matrix above are skipped for Traefik.

```bash
export TF_VAR_traefik_hub_token=<your-hub-token>
```

### One-command setup

```bash
make up                  # k3d cluster + deploy every gateway enabled in local.tfvars
make test-all            # run k6 against every provider + the upstream baseline
make teardown            # destroy everything
```

### Step-by-step

```bash
# 1. Create the k3d cluster with tainted node pools
make cluster CLUSTER_PROVIDER=k3d

# 2. Deploy gateways + dependencies (uses local.tfvars for k3d, cloud.tfvars otherwise)
make deploy

# 3. Run tests
make test-traefik                             # single provider
make test-all                                 # all providers + upstream baseline

# 4. Cleanup
make teardown
```

To deploy a subset of providers, override `apim_providers` on the command line (versions come from the tfvars file):

```bash
cd deployments && terraform apply -var-file=local.tfvars \
  -var='apim_providers={traefik={enabled=true,version="v3.6.13"},kong={enabled=false,version="3.9.1"},tyk={enabled=false,version="v5.11.0"},gravitee={enabled=false,version="4.11.4"},envoygateway={enabled=false,version="v1.7.2"}}'
```

## Architecture

```
clusters/<provider>/   (Terraform)  → cluster + tainted/labeled node pools
                                        │
                                        ▼
deployments/           (Terraform)  → Helm releases:
                                        - dependencies (Grafana stack, cert-manager,
                                          k6-operator, Keycloak, OTel Collector)
                                        - per-provider gateways + Fortio upstream
                                        │
                                        ▼
tests/                 (Make+kubectl) → k6 TestRun CRDs; metrics stream into
                                        Prometheus via remote-write, tagged
                                        testid=<provider>
```

### Node isolation

Each provider gets three dedicated node pools, all tainted `NoSchedule`:

| Node taint               | Hosts                                                           |
|--------------------------|-----------------------------------------------------------------|
| `dependencies` (no taint)| Grafana, Prometheus, Loki, Tempo, OTel Collector, k6-operator, cert-manager, Keycloak, dependencies-Traefik |
| `<provider>`             | Gateway pods (and their required backing stores: Kong/Tyk Redis, Gravitee Redis + Postgres) |
| `<provider>-upstream`    | Fortio backend                                                  |
| `<provider>-loadgen`     | k6 initializer / starter / runner pods                          |

Where `<provider>` ∈ `{traefik, kong, tyk, gravitee, envoygateway, upstream}`. The `upstream` entry is the no-gateway baseline — it has no gateway node, just `upstream-upstream` (well, `upstream`) and `upstream-loadgen`.

**Every pod gets both a `nodeSelector: {node: <taint>}` and a matching toleration.** If anything schedules on the wrong node, results are invalid. Verify with:

```bash
kubectl --context=k3d-benchmark get pods -A -o wide | awk '{print $1,$2,$8}' | sort -k3
```

## Configuration

### Cluster — `clusters/<provider>/terraform.tfvars`

Each `clusters/<cloud>/` subdirectory auto-loads its own `terraform.tfvars`. The k3d variant:

```hcl
apim_providers           = ["traefik", "kong", "tyk", "gravitee", "envoygateway", "upstream"]
apim_provider_node_count = 1
upstream_node_count      = 1
loadgen_node_count       = 1
dependencies_node_count  = 1
```

With the full six-provider list and one node per role, the k3d cluster boots **19 containers** (1 server + 1 dependencies + 5 gateway + 6 upstream + 6 loadgen). For faster iteration, trim to `["traefik", "upstream"]` → 7 containers.

### Deployments — `deployments/local.tfvars` (k3d) / `deployments/cloud.tfvars`

Controls which gateways are enabled, resource limits, and middleware. Key middleware options:

```hcl
apim_providers_middlewares = {
  auth = {
    type      = "disabled"    # disabled | token_iac | token_postgres | jwt_hmac | jwt_keycloak
    app_count = 1
  }
  rate_limit = { enabled = false, rate = 999999, per = 1 }
  quota      = { enabled = false, rate = 999999, per = 3600 }
  tls        = { enabled = false }
  headers = {
    request  = { set = {}, remove = [] }
    response = { set = {}, remove = [] }
  }
  observability = {
    metrics = { enabled = false }
    logs    = { enabled = false }
    traces  = { enabled = false }
  }
}
```

### Tests — `tests/config/k3d.env`

```env
EXECUTOR=constant-arrival-rate
RATE=100              # requests per second
VIRTUAL_USERS=10      # pre-allocated VUs
DURATION=1            # minutes
```

For cloud benchmarks use `tests/config/cloud.env` (5 k RPS, 50 VUs, 15 min).

## Make Targets

Run `make help` for the full list. Key targets:

| Target                                           | Description                                                |
|--------------------------------------------------|------------------------------------------------------------|
| `make cluster`                                   | Create the k8s cluster (uses `clusters/$(CLUSTER_PROVIDER)/terraform.tfvars`) |
| `make deploy`                                    | Deploy gateways + dependencies (uses `local.tfvars` for k3d, `cloud.tfvars` otherwise) |
| `make up`                                        | `cluster` + `deploy`                                       |
| `make test-traefik` (kong, tyk, gravitee, envoygateway, upstream) | Run k6 test against one provider              |
| `make test-all`                                  | Benchmark every provider + the upstream baseline sequentially, with a settle pause between runs |
| `make status`                                    | Show cluster and pod status                                |
| `make validate-nodes`                            | Assert every provider pool has matching instance type / CPU / memory (cloud sanity check) |
| `make -C tests validate-test PROVIDER=<x>`       | 60 s probe + assert placement + assert metrics ingested. Use before every cloud run. |
| `make -C tests summary PROVIDER=<x>`             | Extract the per-run JSON summary block emitted by k6's `handleSummary()` from the runner log |
| `make teardown`                                  | Destroy deployments then cluster                           |
| `make validate`                                  | Terraform fmt + validate                                   |

## Viewing results

### Grafana dashboard

The `k6-test-results` dashboard is imported automatically during `make deploy`. Reach it via port-forward:

```bash
kubectl --context=k3d-benchmark -n dependencies port-forward svc/grafana 3000:80
# browse http://localhost:3000 — default creds: admin / <the randomly-generated password>
kubectl --context=k3d-benchmark -n dependencies get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

The dashboard queries Prometheus metrics prefixed with `k6_` (k6 v0.48+ default) and joined on the `testid=<provider>` tag. Node-scoped panels use the `node=<role>` label the cluster stage sets on each worker.

### Quick sanity checks

```bash
# Confirm Prometheus received k6 data
kubectl --context=k3d-benchmark -n dependencies port-forward svc/prometheus-kube-prometheus-prometheus 9090 &
curl -s 'http://localhost:9090/api/v1/query?query=sum%20by(testid)%20(k6_http_reqs_total)' | jq
```

## Cloud / Self-Managed Clusters

For production-grade benchmarks on cloud infrastructure:

```bash
# 1. Create a cluster for the target cloud (auto-loads that dir's terraform.tfvars)
make cluster CLUSTER_PROVIDER=gke          # or eks, aks, oke, lke, doks

# 2. Deploy gateways (auto-picks cloud.tfvars for non-k3d providers)
make deploy CLUSTER_PROVIDER=gke

# 3. Run tests with cloud config (5 k RPS, 50 VUs, 15 min)
make test-all CONFIG=cloud KUBE_CONTEXT=gke-benchmark
```

### Node labeling requirements (bring-your-own-cluster only)

If you're not using the shipped `clusters/<provider>/` modules, you must label and taint nodes yourself. One pool per role:

```bash
kubectl label nodes <node>  node=dependencies
kubectl label nodes <node>  node=traefik
kubectl taint  nodes <node> node=traefik:NoSchedule
kubectl label nodes <node>  node=traefik-upstream
kubectl taint  nodes <node> node=traefik-upstream:NoSchedule
kubectl label nodes <node>  node=traefik-loadgen
kubectl taint  nodes <node> node=traefik-loadgen:NoSchedule
# ... repeat per provider
```

### Fair cross-cloud comparison

Node instance types must be equivalent — not just "similarly named". The `terraform.tfvars` defaults:

| Cloud | Default instance type   |
|-------|-------------------------|
| EKS   | `m5.xlarge`             |
| GKE   | `n2-standard-2`         |
| AKS   | `Standard_D2s_v3`       |
| LKE   | `g6-dedicated-2`        |
| DOKS  | `s-4vcpu-8gb`           |
| OKE   | `VM.Standard.E4.Flex`   |

These are **not** equivalent on vCPU / RAM / network performance. Normalize before publishing results.

## Orientation for contributors

See [CLAUDE.md](CLAUDE.md) for the project's fairness contract, pipeline stages, known gotchas, and validated results from the last end-to-end run.
