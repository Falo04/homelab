# homelab

HashiCorp Vault, published to the internet through a **Cloudflare Tunnel**.
`cloudflared` runs beside Vault and forwards to it over a private Docker network;
Cloudflare's edge terminates TLS. No host ports are exposed and there's no reverse
proxy or certificate management to run.

## Prerequisites

- Docker + Compose plugin, and [`just`](https://github.com/casey/just)
- A domain in Cloudflare and a **Cloudflare Tunnel** (Zero Trust → Networks →
  Tunnels) with its **tunnel token**

## Setup

1. Create `.env` (gitignored) in the repo root:

   ```env
   TUNNEL_TOKEN=your-tunnel-token
   ```

2. In the Cloudflare dashboard, add a **public hostname** to your tunnel:
   - Domain: e.g. `vault.example.com`
   - Service: **HTTP** → `vault:8200`

   `cloudflared` resolves `vault` via Docker's embedded DNS (shared compose
   network). This also creates the proxied DNS record and Cloudflare issues the
   public cert automatically.

3. Start it:

   ```bash
   just up      # Vault + cloudflared   (just = list all recipes)
   ```

> Vault is now reachable from anywhere (incl. your Kubernetes cluster). Vault's
> own auth is the security boundary — consider **Cloudflare Access** in front of
> the hostname for an extra layer.

## Initialize Vault (first run only)

See [blog post](https://support.hashicorp.com/hc/en-us/articles/41778354863379-Vault-server-cluster-deployment-and-version-upgrade-via-docker-compose) for more information

Vault starts **sealed and uninitialized**. Initialize once, then unseal (repeat
with enough key shares to meet the threshold). Save the unseal keys and root
token — they're shown only once.

```bash
just exec vault vault operator init
just exec vault vault operator unseal   # once per required key share
```

Vault must be unsealed again after every container restart (unless you configure
auto-unseal). Point the CLI at it with `export VAULT_ADDR=https://vault.example.com`.

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
just update vault                       # pull + recreate
just exec vault vault operator unseal   # comes up sealed; repeat to threshold
just exec vault vault status            # check Version + Sealed=false
```

Don't skip more than one minor line without checking the
[upgrade guides](https://developer.hashicorp.com/vault/docs/upgrading/upgrade-guides).
To roll back a bad upgrade: restore the backed-up `data/` (or the snapshot), pin
the previous tag, `just up vault`, unseal.

**cloudflared** (`cloudflare/cloudflared`, unpinned) — stateless (config lives in
the Cloudflare dashboard); `just update vault` pulls and recreates it too. Pin a
tag if you want reproducible upgrades.
