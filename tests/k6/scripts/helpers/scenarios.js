// duration is a bare number; duration_unit defaults to "m" (minutes) but the
// validate-test target passes "s" so it can run a 30-second probe instead
// of the 1-minute minimum.
const getScenarios = ({ ramping_steps, duration, duration_unit, rate, virtual_users }) => {
  const unit = duration_unit || "m";
  return ({
  "constant-vus": {
    executor: 'constant-vus',
    vus: virtual_users,
    duration: duration + unit,
  },
  "ramping-vus": {
    executor: 'ramping-vus',
    stages: [...Array(ramping_steps)].map((_, i) =>
      ({
        target: virtual_users * ((i + 1) / ramping_steps),
        duration: (duration * (1 / ramping_steps)) + unit,
      })
    ),
  },
  "constant-arrival-rate": {
    executor: 'constant-arrival-rate',
    duration: duration + unit,
    rate: rate,
    timeUnit: '1s',
    preAllocatedVUs: virtual_users,
  },
  "ramping-arrival-rate": {
    executor: 'ramping-arrival-rate',
    startRate: 1000,
    timeUnit: '1s',
    preAllocatedVUs: virtual_users,
    stages: [ ...([...Array(ramping_steps)].map((_, i) =>
      ({
        target: rate * ((i + 1) / ramping_steps),
        duration: '6s',
      })
    )), {
      target: rate,
      duration: (duration - ramping_steps * 0.1) + unit,
    }],
  },
  "externally-controlled": {
    executor: 'externally-controlled',
    duration: duration + unit,
    vus: 10,
    maxVUs: virtual_users,
  },
  });
};

export { getScenarios };
