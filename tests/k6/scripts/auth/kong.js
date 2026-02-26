// Kong DB-less mode: consumers and key-auth credentials are provisioned
// via KongConsumer CRDs and Kubernetes Secrets in Terraform.
// Keys follow the pattern "benchmark-key-{index}".
const appCount = parseInt(__ENV.APP_COUNT || "1", 10);

const generateKeys = (keyCount) => {
  const keys = [];
  for (let i = 0; i < keyCount; i++) {
    keys.push("benchmark-key-" + (i % appCount));
  }
  return keys;
};

export { generateKeys };
