// Traefik does not currently support auth-token middleware in this benchmark.
// This is a stub so the test runner can load auth.js uniformly for all providers.
const generateKeys = (keyCount) => [];

export { generateKeys };
