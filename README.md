# homelab

## Prerequisites

- Docker + Docker Compose plugin
- [`just`](https://github.com/casey/just)
- A domain managed in Cloudflare
- A Cloudflare API **token** (not the global key) scoped to:
  - **Zone → DNS → Edit**
  - **Zone → Zone → Read**

  restricted to the zone(s) you use.

## 1. Configure environment

Two env files are loaded by the justfile.

### `.env` (repo root, shared by all stacks)

```env
ROOT_DOMAIN=example.com
```

### `traefik/enviromnet.env` (Cloudflare/ACME tuning)

```env
HTTP_TIMEOUT=60
POLLING_INTERVAL=5
PROPAGATION_TIMEOUT=600
TTL=120
LOG_LEVEL=INFO
```

> These files contain no secrets, but `.env` is gitignored anyway. Copy the
> snippets above and adjust the values for your setup.

## 2. Provide the Cloudflare token

Traefik needs the Cloudflare token **at startup** to solve the DNS-01 challenge
and issue certificates — it is a bootstrap credential. It's mounted as a Docker
secret from a file:

```bash
printf '%s' 'YOUR_CLOUDFLARE_API_TOKEN' > traefik/cloudflare-token.txt
```

This file is **gitignored** and must never be committed.

## 3. Start the stacks

The `up` recipe creates the shared `internal` network automatically.

```bash
just up          # start everything (traefik + vault)
just up traefik  # or start a single stack
just up vault
```

Run `just` with no arguments to list all recipes.

## 4. Initialize Vault (first run only)

Vault starts **sealed and uninitialized**. Initialize it once:

```bash
just exec vault vault operator init
```

Save the **unseal keys** and **root token** it prints somewhere safe — they are
shown only once. Then unseal (repeat with enough keys to meet the threshold):

```bash
just exec vault vault operator unseal   # run for each required key share
```

Vault must be unsealed again after every restart of the container (unless you
configure auto-unseal).

## 5. Access

Once certs are issued (the first issuance can take a few minutes due to the
DNS-01 propagation delay), the services are reachable at:

- `https://traefik.${ROOT_DOMAIN}` — Traefik dashboard
- `https://whoami.${ROOT_DOMAIN}` — test service
- `https://vault.${ROOT_DOMAIN}` — Vault UI

## Notes

- HTTP (`:80`) is permanently redirected to HTTPS (`:443`).
- Certificates are stored in the `acme` Docker volume (`letsencrypt.json`).
- Vault data lives in `vault-cluster/vault1/data` (Raft storage) and listens
  internally on `http://vault:8200` with TLS disabled — TLS is terminated at
  Traefik.
- If the first cert issuance fails, check `just logs traefik` for Cloudflare
  auth errors (usually a bad or under-scoped token).
