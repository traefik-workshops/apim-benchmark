# CLAUDE.md

Orientation for future Claude sessions working in this repo. See [README.md](README.md) for the user-facing quick start.

## What this project is

Fair, reproducible benchmarks for Kubernetes API gateways: **Traefik Hub, Kong OSS, Tyk OSS, Gravitee, Envoy Gateway**. The competing gateway is the only variable — everything around it (cluster, dependencies, load generator, upstream, observability) is held identical.

Originated from `TykTechnologies/tyk-performance-testing`; restructured to be provider-neutral.

## The fairness contract (read this first)

Everything hinges on **node-level isolation inside one shared cluster**. Each provider owns three dedicated node pools, tainted `NoSchedule` so nothing else can land there:

| Role                      | Taint / label             | Hosts                                             |
|---------------------------|---------------------------|---------------------------------------------------|
| dependencies (untainted)  | `node=dependencies`       | Grafana, Prometheus, Loki, Tempo, OTel Collector, k6-operator, cert-manager, Keycloak, dependencies-Traefik |
| `<provider>` gateway      | `node=<provider>`         | Gateway pod(s) **and their backing stores** (Kong/Tyk Redis, Gravitee Redis + Postgres) |
| `<provider>-upstream`     | `node=<provider>-upstream`| Fortio backend for that provider                  |
| `<provider>-loadgen`      | `node=<provider>-loadgen` | k6 initializer/starter/runner pods                |

Where `<provider>` ∈ `{traefik, kong, tyk, gravitee, envoygateway, upstream}` (`upstream` is the "no-gateway" baseline; it has no gateway node, just upstream + loadgen).

Every pod sets both a `nodeSelector: {node: <taint>}` and a matching toleration. If something schedules on the wrong node, results are invalid. When debugging weird numbers, verify pod placement first:

```bash
kubectl get pods -A -o wide | awk '{print $1, $2, $8}' | sort -k3
```

Or use the Makefile's sanity-check targets (below).

The dependencies node is deliberately untainted and placed first in `all_nodes` ([clusters/shared/main.tf:26-37](clusters/shared/main.tf)), so it becomes the default pool on managed clouds that ignore taints for system daemons.

## Three-stage pipeline

```
1. clusters/<provider>/   (Terraform)  → cluster + labeled/tainted node pools
2. deployments/           (Terraform)  → Helm: gateways + dependencies + Fortio upstreams
3. tests/                 (Make+kubectl) → k6 TestRun CRDs; results stream to Prometheus
```

Each stage has its own Terraform state; they are applied in order and destroyed in reverse.

## Directory map

```
clusters/
  k3d/   main.tf + terraform.tfvars              # local Docker cluster (starting point)
  eks/ gke/ aks/ oke/ lke/ doks/                 # cloud counterparts
  shared/main.tf                                 # generates worker_nodes list from apim_providers
deployments/
  main.tf                                        # wires dependencies + 5 providers + baseline upstream
  versions.tf                                    # single source of truth for Helm chart versions
  local.tfvars                                   # context=k3d-benchmark
  cloud.tfvars                                   # context=gke-benchmark (override -var kubernetes_config_context)
  secrets.auto.tfvars                            # gitignored; Hub token + any machine-local overrides
  modules/
    dependencies/                                # Grafana stack, k6-operator, Keycloak, cert-manager,
                                                 #   OTel Collector, dependencies-Traefik
    providers/{traefik,kong,tyk,gravitee,envoygateway,upstream}/
tests/
  Makefile                                       # kubectl-only test driver
  config/{k3d.env,cloud.env}                     # k6 parameters (RATE, DURATION, AUTH_TYPE, ...)
  k6/scripts/{test.js,helpers/,auth/<provider>.js}
  k6/manifests/k6-test.yaml                      # envsubst → k6-operator TestRun CRD
Makefile                                         # top-level orchestrator
```

## Required external state

Two sibling repos must be cloned next to this one (default chart paths and the `../../../..` Terraform source refs assume this layout):

- `../terraform-demo-modules/` — referenced via `../../../../terraform-demo-modules/...` from [deployments/modules/dependencies/main.tf](deployments/modules/dependencies/main.tf) (traefik, cert-manager, k6-operator, keycloak, grafana-stack, opentelemetry).
- `../traefik-demo-resources/` — supplies the local Keycloak + dns-traefiker Helm charts. Paths are resolved via `${path.root}/../../traefik-demo-resources/...` by default; override with `TF_VAR_keycloak_chart` / `TF_VAR_dns_traefiker_chart` if your checkout lives elsewhere.

Clusters, by contrast, pull their underlying modules from the remote git repo `git::https://github.com/traefik-workshops/terraform-demo-modules.git` ([clusters/k3d/main.tf:12](clusters/k3d/main.tf)).

## Required secrets

- `TF_VAR_traefik_hub_token` — Traefik Hub license JWT. If unset, Traefik deploys as OSS (Hub-specific middleware rows in the matrix are skipped for Traefik). You can either export the env var or drop it into a machine-local `deployments/secrets.auto.tfvars` (gitignored).

## Tooling

| Tool       | Why                                     |
|------------|-----------------------------------------|
| Docker     | Backs k3d; no other purpose             |
| k3d v5+    | Local cluster (19 nodes with default tfvars) |
| Terraform 1.5+ | Both cluster and deployment stages  |
| kubectl    | Tests apply YAML directly               |
| helm       | Implicit via Terraform helm provider    |
| envsubst   | `tests/Makefile` substitutes `${VAR}` into the TestRun CRD |
| python3 + bc | `make validate-test` arithmetic      |

Cloud provider CLIs (`aws`, `gcloud`, `az`, `oci`, `doctl`, `linode-cli`) are needed only for their respective `clusters/<cloud>/` stage.

## Supported configurations

Provider coverage for each middleware (from [README.md](README.md)):

| Middleware            | Traefik Hub | Kong OSS | Tyk OSS | Gravitee | Envoy Gateway |
|-----------------------|:-----------:|:--------:|:-------:|:--------:|:-------------:|
| Baseline (no auth)    | ✓ | ✓ | ✓ | ✓ | ✓ |
| Rate Limiting         | ✓ | ✓ | ✓ | ✓ | ✗ |
| Quota                 | ✓ | via RL | ✓ | via RL | ✗ |
| Auth Token (IAC)      | ✓ | ✓ | ✓ | ✓ | ✗ |
| JWT HMAC (HS256)      | ✓ | ✓ | ✓ | ✓ | ✗ |
| JWT Keycloak (RS256)  | ✓ | ✓ | ✓ | ✓ | ✓ |
| Header Manipulation   | ✓ | ✓ | ✓ | ✓ | ✓ |
| TLS Termination       | ✓ | ✓ | ✓ | ✗ | ✓ |
| OTLP Metrics          | ✓ | ✗ | via Pump | ✗ | ✓ |
| OTLP Logs             | ✓ | ✗ | ✗ | ✗ | ✓ |
| OTLP Traces           | ✓ | ✓ | ✓ | ✗ | ✓ |

Auth types: `disabled | token_iac | token_postgres | jwt_hmac | jwt_keycloak`. Controlled in [deployments/local.tfvars](deployments/local.tfvars) via `apim_providers_middlewares.auth.type`.

When comparing providers, **only use rows where every compared provider is ✓**. Enabling `rate_limit` on Kong but relying on its "via RL" cell to stand in for quota is not apples-to-apples.

## Middleware config flow

A single `apim_providers_middlewares` struct in the tfvars gets translated per-provider into native CRDs:

- Traefik → `Middleware`, `APIAuth`, `APIRateLimit`, `ManagedApplication`, `IngressRoute`
- Kong → `KongPlugin` (key-auth, jwt, rate-limiting, request-transformer, opentelemetry) + `KongConsumer`
- Tyk → JSON API definitions in a ConfigMap
- Gravitee → GKO `ApiDefinition` + `Plan` CRDs (gated on Management API readiness before apply — see [providers/gravitee/ingress.tf](deployments/modules/providers/gravitee/ingress.tf) `null_resource.wait_apim_api`)
- Envoy Gateway → `SecurityPolicy`, `BackendTrafficPolicy`, Gateway API `HTTPRoute`

Kong's `jwt_keycloak` path is unusual — Terraform runs a `null_resource` `local-exec` that `kubectl exec`s into a Keycloak pod to fetch the RSA public key, then creates a k8s Secret. If Kong jwt_keycloak fails, that `local-exec` is the likely culprit.

## Test flow (important details)

1. `tests/Makefile` (PROVIDER=traefik, CONFIG=k3d) loads [tests/config/k3d.env](tests/config/k3d.env) and exports the vars.
2. `configmaps` target creates 4 ConfigMaps in the provider's namespace:
   - `test-script-configmap` (test.js) · `tests-configmap` (tests.js) · `scenarios-configmap` (scenarios.js) · `auth-configmap` (auth/`$PROVIDER`.js)
3. `k6-test` target runs `envsubst < k6-test.yaml | kubectl apply -f -`. The TestRun is pinned to `node: <provider>-loadgen` for initializer, starter, runner, with podAntiAffinity so they spread across the loadgen nodes.
4. k6 runner pods push metrics via `--out experimental-prometheus-rw` to `http://prometheus-kube-prometheus-prometheus.dependencies.svc:9090/api/v1/write` with tag `testid=<provider>`.
5. Runner's `handleSummary()` also emits a JSON summary block to stdout bracketed with `K6_SUMMARY_BEGIN / K6_SUMMARY_END` — `make -C tests summary PROVIDER=<x>` extracts it for archival ([tests/k6/scripts/test.js](tests/k6/scripts/test.js)).
6. `test.js` reads env vars, selects a scenario from `scenarios.js`, generates auth keys in `setup()` via `helpers/tests.js` (Keycloak OAuth password grant for RS256, local HMAC signing for HS256, provider-specific calls for token auth), and hits `http://<service>.<namespace>.svc:<port>/api-<i>/?<FORTIO_OPTIONS>`.

Service/port mapping per provider is in [tests/Makefile:25-40](tests/Makefile):

| Provider      | Service (in namespace=provider)        | Port  |
|---------------|----------------------------------------|-------|
| traefik       | `traefik`                              | 80    |
| kong          | `kong-gateway-proxy`                   | 80    |
| tyk           | `gateway-svc-tyk-tyk-gateway`          | 8080  |
| gravitee      | `gravitee-apim-gateway`                | 82    |
| envoygateway  | `envoy-gateway-proxy`                  | 8080  |
| upstream      | `fortio` (baseline — bypasses gateway) | 8080  |

## Grafana dashboard

The dashboard that validates results is [deployments/modules/dependencies/dashboards/k6-test-results.json](deployments/modules/dependencies/dashboards/k6-test-results.json) (~14 k lines). It imports as `k6-test-results` via `extra_dashboards` in the grafana-stack module call.

Access:

```bash
kubectl -n dependencies port-forward svc/grafana 3000:80
# browse http://localhost:3000 — username: admin, password:
kubectl -n dependencies get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

Queries assume:

- Prometheus label `testid=<provider>` (injected by k6-operator `TestRun --tag testid=${PROVIDER}`)
- Metrics prefixed with `k6_` (k6 v0.48+ default). Counter names end in `_total` — e.g. `k6_http_reqs_total`, not `http_reqs`.
- Node label `node=<role>` (set by the cluster stage)
- Remote-write receiver enabled: `enableRemoteWriteReceiver: true` ([deployments/modules/dependencies/main.tf](deployments/modules/dependencies/main.tf))

Validating the dashboard:

1. Use `make -C tests validate-test PROVIDER=traefik` right after a deploy — it runs a 60 s probe, asserts pod placement, and checks Prometheus ingested the testid's samples. Fast enough to use before a full cloud run.
2. After a manual test, query `sum by(testid)(max_over_time(k6_http_reqs_total[30m]))` in Prometheus → one series per tested provider, all ≥ 6000 at 100 RPS / 60 s config.
3. The dashboard's "Test Information" row shows the `k6_deployment_config_*` gauges from [tests/k6/scripts/helpers/tests.js](tests/k6/scripts/helpers/tests.js) — "No data" there means the k6 run didn't hit remote-write successfully.
4. Node-scoped panels (CPU, memory) use `label_node="traefik"` etc. via a `kube_node_labels` join. If they're blank, `prometheus-node-exporter` isn't scraping the tainted nodes. That exporter has a blanket `Exists`/`NoSchedule` toleration ([dependencies/main.tf](deployments/modules/dependencies/main.tf)) specifically to cover all tainted nodes.

## Knowledge notes (stack behaviour that bites when forgotten)

- **k3d with all 6 providers = 19 containers** (1 server + 5 provider + 6 upstream + 6 loadgen + 1 dependencies). Boots but consumes substantial RAM. For quick iteration, trim `clusters/k3d/terraform.tfvars` to `apim_providers = ["traefik", "upstream"]` → 7 containers.
- **`make clean` deletes Terraform state** after `teardown`. Surprising if you expected it to only delete the cluster.
- **Gravitee has no TLS** in the matrix (see provider table). Flipping `tls.enabled = true` with Gravitee enabled lets Terraform apply succeed but Gravitee simply ignores the TLS block — don't read its "TLS" benchmark row against the others.
- **Traefik Helm chart v39.x ships its CRDs via `templates/`, not `crds/`.** Even with `skip_crds = true`, Kubernetes gets the CRDs — the Helm provider's `skip_crds` flag only suppresses the chart's `crds/` directory. Don't assume `skip_crds` buys you independent CRD management here; apply order is determined by the Helm release dependency graph, so the first apply's Keycloak step can still race the Middleware CRD. A second `terraform apply` always resolves the race.
- **k6 metrics carry the `k6_` prefix** (k6 v0.48+ default). All dashboard queries use that prefix, but anyone hand-typing `http_reqs` in Prometheus will see empty results. The counter suffix is `_total`.
- **Prometheus remote-write staleness is ~5 min.** Metric *names* persist but *samples* evict quickly — so `sum(k6_http_reqs_total{testid="traefik"})` returns empty 5 min after a run. Use `max_over_time(...[30m])` or `last_over_time(...[5m:15s])` for historical queries. For back-to-back provider comparisons, run `test-all` and query within ~3 min of completion.
- **k3d's `local-path` provisioner pins every PV to its first-consumer node.** If you later reassign a StatefulSet to a different node via `nodeSelector`, the pod goes `Pending` with "volume node affinity conflict". That's why all benchmark backing stores (`persistence.enabled = false`) use `emptyDir` — a short-lived benchmark doesn't need durability and `emptyDir` also guarantees a clean state per run.

## Validated version pins (2026-04 latest stable)

Single source of truth: [deployments/versions.tf](deployments/versions.tf). Bump there and re-run `make -C tests validate-test PROVIDER=<x>` on k3d before pushing to cloud.

| Component                    | Pinned version | Source                                                                                                           |
|------------------------------|----------------|------------------------------------------------------------------------------------------------------------------|
| Traefik Hub image            | v3.19.4        | [providers/traefik/main.tf](deployments/modules/providers/traefik/main.tf) (hardcoded — chart rejects < v3.19.3) |
| Traefik Helm chart (provider)| 39.0.8         | `versions.tf: chart_versions.traefik`                                                                            |
| Traefik Helm chart (deps)    | 39.0.8         | `versions.tf: chart_versions.dep_traefik`                                                                        |
| Traefik OSS image (non-Hub)  | v3.6.13        | tfvars `apim_providers.traefik.version`                                                                          |
| Kong ingress chart           | 0.24.0         | `versions.tf: chart_versions.kong`                                                                               |
| Kong gateway image           | 3.9.1          | tfvars `apim_providers.kong.version`                                                                             |
| Tyk OSS chart                | 5.1.1          | `versions.tf: chart_versions.tyk`                                                                                |
| Tyk gateway image            | v5.11.0        | tfvars `apim_providers.tyk.version`                                                                              |
| Gravitee APIM chart          | 4.11.4         | `versions.tf: chart_versions.gravitee`                                                                           |
| Gravitee image               | 4.11.4         | tfvars `apim_providers.gravitee.version`                                                                         |
| Envoy Gateway chart + image  | v1.7.2         | tfvars `apim_providers.envoygateway.version` (chart version = image tag)                                         |
| OpenTelemetry Collector chart| 0.127.2        | [terraform-demo-modules/observability/opentelemetry/k8s/main.tf](../terraform-demo-modules/observability/opentelemetry/k8s/main.tf) |

## Validated k3d smoke-test results

Pure proxy overhead (AUTH disabled, single route, ephemeral Redis/Postgres), each gateway on its own tainted node. **Smoke test only**, 60 s × 100 RPS × 1 VU — not a publishable benchmark. Numbers from `last_over_time(k6_http_req_duration_p*[5m])` immediately after `make test-all`.

| Gateway         | p75    | p95    | p99    | p95 overhead vs baseline |
|-----------------|--------|--------|--------|--------------------------|
| `upstream` (no gateway) | 0.42 ms | 0.64 ms | 1.46 ms | — (baseline)           |
| Traefik Hub     | 0.75 ms | 1.04 ms | 2.02 ms | +0.40 ms               |
| Kong OSS        | 0.82 ms | 1.24 ms | 2.61 ms | +0.60 ms               |
| Envoy Gateway   | 0.88 ms | 1.45 ms | 3.70 ms | +0.81 ms               |
| Gravitee        | 1.46 ms | 2.04 ms | 3.89 ms | +1.40 ms               |
| Tyk OSS         | 0.94 ms | 2.72 ms | 5.60 ms | +2.08 ms               |

Caveats on these specific numbers:

- **k3d is 19 Docker containers on one host** — no real CPU-isolation between "provider" and "upstream" nodes. At light load every node sits at ~5 % CPU. Real divergence only shows under cloud nodes with actual CPU/memory pressure.
- **Gravitee's JVM isn't warmed.** The first ~10 s of its run carry JIT tax. We intentionally do **not** add a warmup ramp — that would hide a real, legitimately-measurable cold-start cost. Read the first-minute Gravitee number with that in mind.
- **100 RPS × 60 s is a smoke test.** `tests/config/cloud.env` (20 000 RPS × 15 min) is the real benchmark shape.

## Open items / recommended improvements

- **Per-provider warm-up**: we explicitly chose *not* to add this. Cold-start cost is a real property of the gateway and hiding it biases results in favour of slow-to-warm JVM gateways (Gravitee, Tyk). Document it in the report instead.
- **Result export format**: `handleSummary()` emits JSON to stdout today; a follow-up could pipe to a persistent volume for unattended runs.
- **Middleware-row coverage**: the validated baseline only covers `auth = disabled`. Running the full auth / rate-limit / quota / header / tls matrix on k3d and cloud is the remaining benchmark work.

## Common operations

```bash
# Full k3d cycle
make cluster CLUSTER_PROVIDER=k3d       # clusters/k3d/ (auto-loads terraform.tfvars)
make deploy                             # deployments/ (auto-picks local.tfvars for k3d)
make test-all                           # every provider + upstream baseline, sequential
make teardown                           # destroys deployments then cluster

# Per-provider test (manual)
make -C tests run PROVIDER=traefik CONFIG=k3d
make -C tests wait PROVIDER=traefik     # watch pods
make -C tests logs PROVIDER=traefik     # stream runner log
make -C tests summary PROVIDER=traefik  # extract the JSON summary block
make -C tests clean PROVIDER=traefik

# Pre-flight sanity checks
make validate-nodes                     # all provider pools share instance type / CPU / memory
make -C tests validate-test PROVIDER=traefik   # 60 s probe + assert placement + assert metrics

# Inspect placement (fairness check)
kubectl --context=k3d-benchmark get pods -A -o wide \
  | awk '{print $1, $2, $8}' | sort -k3

# Confirm Prometheus received k6 data (within ~5 min of a test; use max_over_time after)
kubectl --context=k3d-benchmark -n dependencies port-forward svc/prometheus-kube-prometheus-prometheus 9090 &
curl -s 'http://localhost:9090/api/v1/query?query=sum+by(testid)(k6_http_reqs_total)' | jq
```

## Cloud runs

1. `make cluster CLUSTER_PROVIDER=<cloud>` — uses `clusters/<cloud>/terraform.tfvars`; set cloud credentials via env or that file.
2. Cluster outputs `kube_context = <name>-benchmark` (e.g. `gke-benchmark`). Ensure your local kubeconfig has that context.
3. `make deploy CLUSTER_PROVIDER=<cloud>` — auto-selects `cloud.tfvars`; override `kubernetes_config_context` via `-var kubernetes_config_context=<ctx>` if your context name differs.
4. `make validate-nodes KUBE_CONTEXT=<ctx>` before running tests — cheap asymmetry catch.
5. `make test-all CLUSTER_PROVIDER=<cloud> KUBE_CONTEXT=<ctx>` — `TEST_CONFIG` auto-resolves to `cloud` → 10 k RPS × 15 min × 50 VUs.

For a truly fair cross-cloud comparison, node instance types must be equivalent, not just "similarly named". Current defaults — `m5.xlarge` (EKS), `n2-standard-2` (GKE), `Standard_D2s_v3` (AKS), `g6-dedicated-2` (LKE), `s-4vcpu-8gb` (DOKS), `VM.Standard.E4.Flex` (OKE) — are **not** equivalent on vCPU / RAM / network. Normalize to one profile (e.g. 4 vCPU / 16 GB / comparable network) and update each cloud's `terraform.tfvars` before publishing results. `make validate-nodes` catches intra-cluster mismatches but cannot catch cross-cluster ones — that's on the reviewer.
