cluster_provider = "lke"
cluster_location = "us-sea"
cluster_node_type = "g6-dedicated-8"

apim_providers = ["traefik", "kong", "tyk", "gravitee", "envoygateway", "upstream"]

apim_provider_node_count = 1
upstream_node_count      = 1
loadgen_node_count       = 1
dependencies_node_count  = 1
