ui = true
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}
storage "raft" {
  path    = "/vault/data"
  node_id = "vault"
}
api_addr = "http://vault:8200"
cluster_addr = "http://vault:8201"
