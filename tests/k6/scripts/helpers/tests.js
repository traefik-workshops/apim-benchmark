import http from 'k6/http';
import { check, fail } from 'k6';
import { Gauge } from 'k6/metrics';
import crypto from 'k6/crypto';
import encoding from 'k6/encoding';

// ---------------------------------------------------------------------------
// Metrics gauges — these appear in Grafana dashboards for test context
// ---------------------------------------------------------------------------
const analyticsGauge       = new Gauge('deployment_config_analytics');
const authGauge            = new Gauge('deployment_config_auth');
const quotaGauge           = new Gauge('deployment_config_quota');
const rateLimitGauge       = new Gauge('deployment_config_rate_limit');
const openTelemetryGauge   = new Gauge('deployment_config_open_telemetry');
const headerInjectionGauge = new Gauge('deployment_config_header_injection');

const durationGauge     = new Gauge('test_config_duration');
const rateGauge         = new Gauge('test_config_rate');
const virtualUsersGauge = new Gauge('test_config_virtual_users');
const fortioOptsGauge   = new Gauge('tests_fortio_options');

const routeCountGauge = new Gauge('service_route_count');
const appCountGauge   = new Gauge('service_app_count');
const hostCountGauge  = new Gauge('service_host_count');

// ---------------------------------------------------------------------------
// Config readers — all sourced from k6 environment variables
// ---------------------------------------------------------------------------
const envBool   = (name) => __ENV[name] === "true";
const envInt    = (name) => parseInt(__ENV[name] || "0", 10);
const envStr    = (name) => __ENV[name] || "";

// getAuth derives from AUTH_TYPE — "disabled" or empty means no auth
const getAuth = () => {
  const authType = envStr("AUTH_TYPE");
  return authType !== "" && authType !== "disabled";
};
const getAuthType  = () => envStr("AUTH_TYPE");
const getRouteCount = () => envInt("ROUTE_COUNT");
const getHostCount  = () => envInt("HOST_COUNT");

// ---------------------------------------------------------------------------
// addTestInfoMetrics — records the test configuration as k6 metrics
// ---------------------------------------------------------------------------
const addTestInfoMetrics = ({ duration, rate, virtual_users, fortio_options }, key_count) => {
  const analyticsDb   = envBool("ANALYTICS_DB_ENABLED");
  const analyticsProm = envBool("ANALYTICS_PROM_ENABLED");
  const analytics = [
    analyticsDb   ? "Database"   : "",
    analyticsProm ? "Prometheus" : "",
  ].filter(item => item !== "");

  analyticsGauge.add(1, {
    state: analytics.length > 0 ? analytics.join(", ") : "Off",
  });

  authGauge.add(1, {
    state: getAuth() ? getAuthType() + " / " + key_count : "Off",
  });

  quotaGauge.add(1, {
    state: envBool("QUOTA_ENABLED")
      ? envStr("QUOTA_RATE") + " / " + envStr("QUOTA_PER")
      : "Off",
  });

  rateLimitGauge.add(1, {
    state: envBool("RATE_LIMIT_ENABLED")
      ? envStr("RATE_LIMIT_RATE") + " / " + envStr("RATE_LIMIT_PER")
      : "Off",
  });

  openTelemetryGauge.add(1, {
    state: envBool("OTEL_ENABLED")
      ? envStr("OTEL_SAMPLING_RATIO")
      : "Off",
  });

  const headerInj = [
    envBool("HEADER_INJ_REQ") ? "Req" : "",
    envBool("HEADER_INJ_RES") ? "Res" : "",
  ].filter(item => item !== "");
  headerInjectionGauge.add(1, {
    state: headerInj.length > 0 ? headerInj.join(" / ") : "Off",
  });

  durationGauge.add(duration);
  rateGauge.add(rate);
  virtualUsersGauge.add(virtual_users);
  fortioOptsGauge.add(1, {
    state: fortio_options ? fortio_options.split("&").join(", ") : "None",
  });

  routeCountGauge.add(getRouteCount());
  appCountGauge.add(envInt("APP_COUNT"));
  hostCountGauge.add(getHostCount());
};

// ---------------------------------------------------------------------------
// JWT helpers
// ---------------------------------------------------------------------------
const generateJWTRSAKeys = (keyCount) => {
  const keys = [];
  const params = { responseType: 'text' };
  const userCount = 10; // matches keycloak module: range(10)

  for (let i = 0; i < keyCount; i++) {
    let payload = {
      client_id: 'traefik',
      grant_type: 'password',
      client_secret: 'NoTgoLZpbrr5QvbNDIRIvmZOhe9wI0r0',
      scope: 'openid',
      username: 'user' + i % userCount + '@test.com',
      password: 'topsecretpassword',
    };

    const res = http.post(
      "http://keycloak-service.dependencies.svc:8080/realms/traefik/protocol/openid-connect/token",
      payload,
      params
    );
    check(res, {
      ['key creation call status is 200']: (r) => r.status === 200,
    }) || fail('Failed to create key');
    keys.push(res.json().access_token);
  }
  return keys;
};

const sign = (data, secret) => {
  const hasher = crypto.createHMAC('sha256', secret);
  hasher.update(data);
  return hasher.digest("base64rawurl");
};

const encode = (payload, secret) => {
  const header = encoding.b64encode(
    JSON.stringify({ typ: "JWT", alg: "HS256" }),
    "rawurl"
  );
  payload = encoding.b64encode(JSON.stringify(payload), "rawurl");
  const sig = sign(header + "." + payload, secret);
  return [header, payload, sig].join(".");
};

const generateJWTHMACKeys = (keyCount) => {
  const keys = [];
  const secret = "topsecretpassword";

  for (let i = 0; i < keyCount; i++) {
    const now = Math.floor(Date.now() / 1000);
    keys.push(encode({
      sub: 'user' + i % 100 + '@test.com',
      iat: now,
      exp: now + 86400,
      iss: "k6",
      jti: 'jwt-' + i + '-' + now
    }, secret));
  }
  return keys;
};

export {
  getAuth,
  getAuthType,
  getRouteCount,
  getHostCount,
  generateJWTRSAKeys,
  generateJWTHMACKeys,
  addTestInfoMetrics,
};
