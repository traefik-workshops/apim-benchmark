# Tests

k6 load tests deployed via `kubectl` and the [k6-operator](https://github.com/grafana/k6-operator) CRD.

## Usage

```bash
# From the repo root:
make test-traefik          # single provider
make test-all              # all providers sequentially

# Or from this directory:
make run PROVIDER=traefik
make wait PROVIDER=traefik
make clean PROVIDER=traefik
```

## Configuration

Test parameters are set via env files in `config/`:

| File          | Purpose                                      |
|---------------|----------------------------------------------|
| `k3d.env`     | Local k3d defaults (500 RPS, 2 min)          |
| `cloud.env`   | Cloud benchmarks (20k RPS, 15 min)           |

Override the config file with `CONFIG=cloud`:

```bash
make run PROVIDER=traefik CONFIG=cloud KUBE_CONTEXT=benchmark
```

### Key variables

| Variable              | Description                          | Default (k3d)   |
|-----------------------|--------------------------------------|------------------|
| `RATE`                | Requests per second                  | `500`            |
| `VIRTUAL_USERS`       | Pre-allocated VUs                    | `10`             |
| `DURATION`            | Test duration (minutes)              | `2`              |
| `AUTH_TYPE`           | `disabled` / `jwt_hmac` / `jwt_keycloak` / `token_iac` | `jwt_keycloak` |
| `USE_TLS`             | Enable TLS termination               | `false`          |
| `ROUTE_COUNT`         | Number of API routes                 | `1`              |
| `OTEL_METRICS_ENABLED`| Export OTLP metrics                  | `true`           |
| `OTEL_TRACES_ENABLED` | Export OTLP traces                   | `true`           |

See `config/k3d.env` for the full list.

## Structure

```
tests/
  Makefile                  # Deploy/run/clean k6 tests via kubectl
  config/
    k3d.env                 # Local test config
    cloud.env               # Cloud test config
  k6/
    scripts/
      test.js               # Main k6 test script
      helpers/
        tests.js            # Test config gauges + JWT helpers
        scenarios.js        # k6 executor scenarios
      auth/
        <provider>.js       # Provider-specific auth key generation
    manifests/
      k6-test.yaml          # k6-operator TestRun CRD template
```

## How it works

1. `make configmaps` creates ConfigMaps from the k6 scripts
2. `make k6-test` runs `envsubst` on `k6-test.yaml` and applies the TestRun CRD
3. The k6-operator creates initializer, starter, and runner pods
4. Runners execute the test and push metrics to Prometheus via remote-write
5. Results are visible in the Grafana dashboard
