cluster_provider = "doks"
cluster_location = "nyc3"
cluster_node_type = "s-4vcpu-8gb"

apim_providers = ["traefik", "kong", "tyk", "gravitee", "envoygateway", "upstream"]

apim_provider_node_count = 1
upstream_node_count      = 1
loadgen_node_count       = 1
dependencies_node_count  = 1
