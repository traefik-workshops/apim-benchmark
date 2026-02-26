import http from 'k6/http';
import { check, fail } from 'k6';

const appCount = parseInt(__ENV.APP_COUNT || "1", 10);
const routeCount = parseInt(__ENV.ROUTE_COUNT || "1", 10);

// Tyk OSS Gateway API — keys are managed via /tyk/keys endpoint.
// The gateway secret is set in tykConfig and defaults to the chart's secret.
const params = {
  responseType: 'text',
  headers: {
    'X-Tyk-Authorization': __ENV.TYK_AUTH || "CHANGEME",
    'Content-Type': 'application/json',
  },
};

const createKey = (baseURL, apiIds) => {
  const accessRights = {};
  for (const apiId of apiIds) {
    accessRights[apiId] = {
      api_id: apiId,
      api_name: apiId,
      versions: ["Default"],
    };
  }

  const payload = JSON.stringify({
    allowance: -1,
    rate: -1,
    per: -1,
    throttle_interval: -1,
    quota_max: -1,
    quota_renewal_rate: -1,
    access_rights: accessRights,
  });

  const res = http.post(baseURL + '/tyk/keys', payload, params);
  check(res, {
    ['key creation call status is 200']: (r) => r.status === 200,
  }) || fail('Failed to create key: ' + res.body);

  return res.json().key;
};

const generateKeys = (keyCount) => {
  const keys = [];
  const baseURL = "http://gateway-svc-tyk-tyk-gateway.tyk.svc:8080";

  // Build list of API IDs that match the API definitions
  const apiIds = [];
  for (let i = 0; i < routeCount; i++) {
    apiIds.push("api-" + i);
  }

  for (let i = 0; i < keyCount; i++) {
    keys.push(createKey(baseURL, apiIds));
  }

  return keys;
};

export { generateKeys };
