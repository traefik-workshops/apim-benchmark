import http from 'k6/http';
import { check, fail } from 'k6';

const routeCount = parseInt(__ENV.ROUTE_COUNT || "1", 10);
const appCount   = parseInt(__ENV.APP_COUNT   || "1", 10);

const getAPIIds = (baseURL, apiCount) => {
  const res = http.get(baseURL + '/apis/?page=1&size=' + apiCount, { responseType: 'text' });
  check(res, {
    'apis get call status is 200': (r) => r.status === 200,
  }) || fail('Failed to get APIs');

  const apiIds = [];
  const data = res.json().data;

  for (let i = 0; i < apiCount; i++) {
    let api = data.find((api) => api.name === "api-" + i);
    check(api, {
      ['api "api-' + i + '" exists']: (a) => a,
    }) || fail('API "api-' + i + '" not found');
    apiIds.push(api.id);
  }

  return apiIds;
};

const getPlanIds = (baseURL, apiIds, planCount) => {
  const planIds = [];
  const apiCount = apiIds.length;

  for (let i = 0; i < planCount; i++) {
    let res = http.get(baseURL + '/apis/' + apiIds[i % apiCount] + '/plans', { responseType: 'text' });
    check(res, {
      'plans get call status is 200': (r) => r.status === 200,
    }) || fail('Failed to get plans');

    let plan = res.json().data.find((plan) => plan.name === "API_KEY");
    check(plan, {
      'plan API_KEY exists': (p) => p,
    }) || fail('Plan "API_KEY" not found');
    planIds.push(plan.id);
  }

  return planIds;
};

const params = {
  responseType: 'text',
  headers: {
    'Authorization': "Basic YWRtaW46YWRtaW4=",
    'Content-Type': 'application/json',
  },
};

const createApplications = (baseURL, keyCount) => {
  const applicationIds = [];
  for (let i = 0; i < keyCount; i++) {
    const name = 'app-' + i;
    const payload = JSON.stringify({
      name: name,
      description: name,
      settings: { app: {} }
    });

    const res = http.post(baseURL + '/applications', payload, params);
    check(res, {
      ['application "' + name + '" creation status is 201']: (r) => r.status === 201,
    }) || fail('Failed to create application "' + name + '"');
    applicationIds.push(res.json().id);
  }

  return applicationIds;
};

const createSubscriptions = (baseURL, planIds, applicationIds) => {
  const keys = [];
  const planCount = planIds.length;
  for (let i = 0; i < applicationIds.length; i++) {
    const payload = JSON.stringify({
      application: applicationIds[i],
      plan: planIds[i % planCount]
    });

    const res = http.post(baseURL + '/subscriptions', payload, params);
    check(res, {
      ['subscription for app "' + applicationIds[i] + '" status is 200']: (r) => r.status === 200,
    }) || fail('Failed to create subscription for application "' + applicationIds[i] + '"');
    keys.push(res.json().keys[0].key);
  }

  return keys;
};

const generateKeys = (keyCount) => {
  const baseURL = "http://gravitee-apim-api:83/portal/environments/DEFAULT";
  const apiIds = getAPIIds(baseURL, routeCount);
  const planIds = getPlanIds(baseURL, apiIds, appCount);
  const applicationIds = createApplications(baseURL, keyCount);
  return createSubscriptions(baseURL, planIds, applicationIds);
};

export { generateKeys };
