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
  host-level install, *not* a compose service. (will change in the future to compose service)

## Setup

1. Create `.env` (gitignored) in this directory:

   ```env
   DOMAIN=int.example.com
   HTTP_TIMEOUT=60
   POLLING_INTERVAL=5
   PROPAGATION_TIMEOUT=600
   TTL=120
   LOG_LEVEL=INFO
   ```

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

```bash
just exec vault vault sh
$ export VAULT_ADDR=http://127.0.0.1:8200
$ vault operator init
$ vault operator unseal <unseal-key>
```

Vault must be unsealed again after every container restart (unless you configure
auto-unseal). From your workstation (on the LAN or tailnet) point the CLI at it
with `export VAULT_ADDR=https://vault.${DOMAIN}`.

## Upgrading

Images are pinned in `vault/docker-compose.yml`. Upgrade by editing the tag →
pull → recreate → verify.

**Vault** (`hashicorp/vault:1.13.3`) — **no downgrades**; once data is written by
a newer version an older binary may refuse to start. Before upgrading, back up
`vault/vault1/data/` and take a snapshot:

```bash
just exec vault vault operator raft snapshot save /vault/data/pre-upgrade.snap
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
the previous tag, `just up`, unseal.

**Traefik** (`traefik:v3.7`) — stateless aside from the ACME store
(`acme` volume). `just update` pulls and recreates it too.
