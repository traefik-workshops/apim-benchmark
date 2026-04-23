import http from 'k6/http';
import {
  getAuth,
  getAuthType,
  getRouteCount,
  getHostCount,
  generateJWTRSAKeys,
  generateJWTHMACKeys,
  addTestInfoMetrics,
} from "/helpers/tests.js";
import { getScenarios } from "/helpers/scenarios.js";
import { generateKeys } from "/helpers/auth.js";

// ---------------------------------------------------------------------------
// Configuration from environment variables
// ---------------------------------------------------------------------------
const { SCENARIO } = __ENV;
const provider      = __ENV.PROVIDER      || "traefik";
const serviceName   = __ENV.SERVICE_NAME  || "traefik";
const servicePort   = __ENV.SERVICE_PORT  || "80";
const namespace     = __ENV.NAMESPACE     || provider;
const fortioOptions = __ENV.FORTIO_OPTIONS || "size=20";
const keyCount      = parseInt(__ENV.KEY_COUNT || "100", 10);
const useTLS        = __ENV.USE_TLS === "true";
const protocol      = useTLS ? "https" : "http";

const config = {
  ramping_steps: parseInt(__ENV.RAMPING_STEPS || "10", 10),
  duration:      parseInt(__ENV.DURATION      || "2",  10),
  duration_unit: __ENV.DURATION_UNIT          || "m",
  rate:          parseInt(__ENV.RATE           || "500", 10),
  virtual_users: parseInt(__ENV.VIRTUAL_USERS  || "10", 10),
  fortio_options: fortioOptions,
};

// ---------------------------------------------------------------------------
// k6 options
// ---------------------------------------------------------------------------
export const options = {
  discardResponseBodies: true,
  insecureSkipTLSVerify: true,
  setupTimeout: '300s',
  scenarios: { [SCENARIO]: getScenarios(config)[SCENARIO] },
};

// ---------------------------------------------------------------------------
// Setup — generate auth keys based on AUTH_TYPE
// Auth types: disabled, token_postgres, token_iac, jwt_hmac, jwt_keycloak
// Legacy types: JWT-RSA (→ jwt_keycloak), JWT-HMAC (→ jwt_hmac)
// ---------------------------------------------------------------------------
export function setup() {
  addTestInfoMetrics(config, keyCount);
  const authType = getAuthType();
  switch (authType) {
    case "jwt_keycloak":
    case "JWT-RSA":
      return generateJWTRSAKeys(keyCount);
    case "jwt_hmac":
    case "JWT-HMAC":
      return generateJWTHMACKeys(keyCount);
    case "token_postgres":
    case "token_iac":
      return generateKeys(keyCount);
    default:
      return {};
  }
}

// ---------------------------------------------------------------------------
// Default function — the actual load test
// ---------------------------------------------------------------------------
export default function (keys) {
  const routeCount = getRouteCount();
  let i = Math.floor(Math.random() * routeCount);

  let headers = {};
  if (getAuth()) {
    const authType = getAuthType();
    // JWT types require "Bearer " prefix (mandatory for Envoy Gateway,
    // accepted by Kong / Tyk / Gravitee which strip it automatically).
    // API-key types (token_iac, token_postgres) use raw value.
    const isJWT = ["jwt_hmac", "jwt_keycloak", "JWT-RSA", "JWT-HMAC"].includes(authType);
    const value = isJWT ? "Bearer " + keys[i % keys.length] : keys[i % keys.length];
    headers = { "Authorization": value };
  }

  let url;
  if (provider === "upstream") {
    const hostCount = getHostCount();
    i = Math.floor(Math.random() * hostCount);
    url = `${protocol}://${serviceName}-${i}.${namespace}.svc:${servicePort}/?${fortioOptions}`;
  } else {
    url = `${protocol}://${serviceName}.${namespace}.svc:${servicePort}/api-${i}/?${fortioOptions}`;
  }

  http.get(url, { headers });
}

// ---------------------------------------------------------------------------
// handleSummary — emits two outputs at end-of-test:
//   1. The default text summary to stdout (unchanged, k6 renders pretty)
//   2. A machine-readable JSON summary to stdout, bracketed with markers so
//      the kubectl-log caller can `awk`/`jq` it out for archival
//
// Prometheus remote-write is still authoritative for time-series; this is
// the complementary "one artefact per run, one provider" snapshot so you
// don't have to snapshot Prom just to keep a number.
// ---------------------------------------------------------------------------
export function handleSummary(data) {
  const picked = {
    provider: __ENV.PROVIDER,
    scenario: __ENV.SCENARIO,
    rate: config.rate,
    virtual_users: config.virtual_users,
    duration_minutes: config.duration,
    auth_type: __ENV.AUTH_TYPE,
    use_tls: useTLS,
    metrics: data.metrics,
    root_group: data.root_group,
    timestamp: new Date().toISOString(),
  };
  return {
    "stdout":
      "\n===== K6_SUMMARY_BEGIN =====\n" +
      JSON.stringify(picked, null, 2) +
      "\n===== K6_SUMMARY_END =====\n",
  };
}
