cluster_location  = "us-chicago-1"
cluster_node_type = "VM.Standard.E4.Flex"
# compartment_id = "ocid1.compartment.oc1..your-compartment-id-here"

apim_providers = ["traefik", "kong", "tyk", "gravitee", "envoygateway", "upstream"]

apim_provider_node_count = 1
upstream_node_count      = 1
loadgen_node_count       = 1
dependencies_node_count  = 1
