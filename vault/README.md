# Vault

Vault behind Traefik at `https://vault.${DOMAIN}`, reachable from the LAN and
from its own tailnet node (`vault`, `tag:vault`).

## Prerequisites

- Docker + Compose plugin, and [`just`](https://github.com/casey/just)
- A Cloudflare API token for the zone: Zone → DNS → Edit, Zone → Zone → Read
- A Tailscale auth key

## Setup

1. `.env` in this directory:

   ```env
   DOMAIN=int.example.com
   HTTP_TIMEOUT=60
   POLLING_INTERVAL=5
   PROPAGATION_TIMEOUT=600
   TTL=120
   # k3s node IPs (LAN) + the tailnet; everything else gets a 403.
   ALLOWED_SOURCES=<k3s-node-1>/32,<k3s-node-2>/32,100.64.0.0/10
   ```

2. Secrets (gitignored):

   ```bash
   echo '<cloudflare-token>' > cloudflare-token.txt
   echo '<tailscale-auth-key>' > tailscale-authkey.txt
   ```

3. `vault-backup.env` for the backup container, see
   [docs/vault-backup.md](/docs/vault-backup.md).

4. Start:

   ```bash
   just up
   ```

5. DNS: point the Cloudflare record `vault.${DOMAIN}` at the `vault` node's
   tailnet IP (`docker exec tailscale tailscale ip -4`). The cluster resolves
   the name to the host's LAN IP via
   [coredns-custom.yaml](/apps/infra/vault-secrets/coredns-custom.yaml).

## Initialize (first run only)

```bash
just exec vault vault operator init
just exec vault vault operator unseal <unseal-key>   # repeat to threshold
```

Save the unseal keys and root token; they are shown only once.

## Configure

```bash
just exec vault vault login <root-token>

# Audit log to stdout (`just logs vault`)
just exec vault vault audit enable file file_path=stdout

# Admin login instead of root
just exec vault sh -c 'vault policy write admin - <<EOF
path "*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
EOF'
just exec vault vault auth enable userpass
just exec vault vault write auth/userpass/users/<you> password=- policies=admin

# Revoke root
just exec vault vault token revoke -self
just exec vault rm -f /root/.vault-token /home/vault/.vault-token
```

From your workstation:

```bash
export VAULT_ADDR=https://vault.${DOMAIN}
vault login -method=userpass username=<you>
```

Vault comes up sealed after every restart; unseal it again with
`just exec vault vault operator unseal`.
