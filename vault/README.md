# HashiCorp Vault (Traefik + Tailscale / LAN)

HashiCorp Vault, fronted by **Traefik**. Traefik terminates TLS with a
Let's Encrypt certificate obtained over the **Cloudflare DNS-01 challenge**, so
no port is ever opened to the public internet.

Vault is reachable at `https://vault.${DOMAIN}` from two places only:

- the **local network** (Traefik listens on the host's `:443`), and
- the **tailnet** — `tailscaled` runs on the Docker host, so the host's tailnet
  address serves the same `:443`.

The Kubernetes cluster reaches Vault the same way (LAN or tailnet), so nothing
about Vault is exposed to the internet.

## Prerequisites

- Docker + Compose plugin, and [`just`](https://github.com/casey/just)
- A Cloudflare API token scoped to (restricted to the zone(s) you use):
  - Zone → DNS → Edit
  - Zone → Zone → Read
- **Tailscale installed and up on the Docker host** (`tailscale up`). This is a
  host-level install, _not_ a compose service. (will change in the future to compose service)

## Setup

1. Create `.env` (gitignored) in this directory:

   ```env
   DOMAIN=int.example.com
   HTTP_TIMEOUT=60
   POLLING_INTERVAL=5
   PROPAGATION_TIMEOUT=600
   TTL=120
   LOG_LEVEL=INFO
   # Who may reach Vault and the dashboard: the k3s nodes plus the tailnet.
   ALLOWED_SOURCES=<k3s-node-1>/32,<k3s-node-2>/32,100.64.0.0/10
   ```

   `ALLOWED_SOURCES` is required: every router uses the `allowlist`
   middleware, so anything outside it gets a 403. List the k3s node IPs (the
   cluster reaches Vault over the LAN) and keep `100.64.0.0/10` for the tailnet.

2. Provide the Cloudflare token (used by Traefik for the DNS-01 challenge):

   ```bash
   echo 'CLOUDFLARE_TOKEN' > cloudflare-token.txt
   ```

   This file is gitignored and must never be committed.

3. Start it:

   ```bash
   just up      # Traefik + Vault   (just = list all recipes)
   ```

   Traefik requests the `vault.${DOMAIN}` certificate on first start; allow a
   moment for the DNS-01 challenge to complete.

## Initialize Vault (first run only)

See this [blog post](https://support.hashicorp.com/hc/en-us/articles/41778354863379-Vault-server-cluster-deployment-and-version-upgrade-via-docker-compose) for more information.

Vault starts **sealed and uninitialized**. Initialize once, then unseal (repeat
with enough key shares to meet the threshold). Save the unseal keys and root
token — they're shown only once.

`VAULT_ADDR` is preset to `http://127.0.0.1:8200` in the container (the
listener runs HTTP; Traefik terminates TLS), so the CLI works directly:

```bash
just exec vault vault operator init
just exec vault vault operator unseal <unseal-key>
```

Privileged commands additionally need a token. Use the root token **only**
for the one-time setup below, then revoke it. `vault login` writes the token to
`~/.vault-token` inside the container, where it would otherwise sit for the
life of the container.

```bash
just exec vault vault login <root-token>

# Audit log: every request, secret paths HMAC'd. Writes to the container's
# stdout, so `just logs vault` shows it.
just exec vault vault audit enable file file_path=stdout

# A day-to-day admin login instead of root.
just exec vault sh -c 'vault policy write admin - <<EOF
path "*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
EOF'
just exec vault vault auth enable userpass
just exec vault vault write auth/userpass/users/<you> password=- policies=admin

# Done with root: revoke it and drop the cached token.
just exec vault vault token revoke -self
just exec vault rm -f /root/.vault-token /home/vault/.vault-token
```

From then on log in with `vault login -method=userpass username=<you>` from
your workstation. If you ever need root again (e.g. a lost admin login),
regenerate it from the unseal keys with `vault operator generate-root` and
revoke it afterwards.

Vault must be unsealed again after every container restart (unless you configure
auto-unseal). From your workstation (on the LAN or tailnet) point the CLI at it
with `export VAULT_ADDR=https://vault.${DOMAIN}`.

## Backups

The `vault-backup` container takes an hourly raft snapshot into a restic
repository on Garage. Setup, retention and the restore procedure are in
[docs/vault-backup.md](/docs/vault-backup.md); it needs a `vault-backup.env` in
this directory before `just up`.

```bash
just backup-status     # newest snapshots
just backup-now        # take one immediately
```

## Upgrading

Images are pinned in [`docker-compose.yml`](./docker-compose.yml).

**Vault** — **no downgrades**; once data is written by
a newer version an older binary may refuse to start. Before upgrading, back up
`vault/vault1/data/` and take a snapshot:

```bash
just exec vault vault login -method=userpass username=<you>   # snapshot needs the admin policy
just exec vault vault operator raft snapshot save /vault/data/pre-upgrade.snap
just exec vault vault token revoke -self
```

Then bump the tag, and:

```bash
just update                             # pull + recreate
just exec vault vault operator unseal   # comes up sealed; repeat to threshold
just exec vault vault status            # check Version + Sealed=false
```

Don't skip more than one minor line without checking the
[upgrade guides](https://developer.hashicorp.com/vault/docs/upgrading/upgrade-guides).
To roll back a bad upgrade: restore the backed-up `data/` (or the snapshot), pin
the previous tag, `just up`, unseal. The hourly snapshots are a second escape
hatch — `just backup-restore` and follow
[docs/vault-backup.md](/docs/vault-backup.md).

**Traefik** — stateless aside from the ACME store
(`acme` volume). `just update` pulls and recreates it too.
